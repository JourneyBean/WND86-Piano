;=============================================
;
; +++++++++++++++++++++++++++++++++++++++++++
; |        微机原理和接口技术 综合设计        |
; +++++++++++++++++++++++++++++++++++++++++++
;
;   ----- 软件功能 -----
;   配套唐都仪器TD-PITE实验环境，实现一个简易电子钟程序。
;   主要功能：
;       弹奏功能：按下按键时播放声音
;       录音功能：边弹奏边录制
;       播放功能：播放内存中的声音
;
;   ----- 使用外设 -----
;       矩阵键盘x1、蜂鸣器x1、数码管x1
;
;   ----- 使用芯片 -----
;       8253定时器、8255并行接口、8259中断
;
;   ----- 使用资源 -----
;       中断x1、IO使能信号口x2
;
;=============================================


; S1 ========== 定义部分 ========== ;

; S1.1 -------- 参数设置部分 -------- ;

; S1.1.1 ------ 用户定义参数 ------ ;

; 定时器输入时钟频率
TIM_CLKSRC_FREQ     equ 1000000
; Systick频率
SYSTICK_FREQ        equ 100
; 数码管扫描速度（Systick分频系数）
SEG_SRV_DUTY        equ 1
; 8254定时器外设地址
M8254_ADDR           equ IOY0
; 8255并口外设地址
M8255_ADDR           equ IOY1

; S1.1.2 ------ 参数计算部分 ------ ;

; SYSTICK分频数
SYSTICK_TIM_COUNT   equ TIM_CLKSRC_FREQ/SYSTICK_FREQ


; S1.2 -------- 地址定义 -------- ;

; 存储器地址定义
DATA_ADDR   equ 0000h

; 端口定义
IOY0        equ 0600h               ; IO使能线0地址
IOY1        equ 0640h               ; IO使能线0地址
IOY2        equ 0680h               ; IO使能线0地址
IOY3        equ 06C0h               ; IO使能线0地址

; 8254定时器芯片
M8254_A      equ M8254_ADDR+00h*2     ; 8254 Channel A
M8254_B      equ M8254_ADDR+01h*2     ; 8254 Channel B
M8254_C      equ M8254_ADDR+02h*2     ; 8254 Channel C
M8254_CTL    equ M8254_ADDR+03h*2     ; 8254 Port Control

; 8255并口芯片
M8255_A      equ M8255_ADDR+00h*2     ; 8255 Port A
M8255_B      equ M8255_ADDR+01h*2     ; 8255 Port B
M8255_C      equ M8255_ADDR+02h*2     ; 8255 Port C
M8255_CTL    equ M8255_ADDR+03h*2     ; 8255 Port Control

; 8259定时器芯片
M8259M_ICW1  equ 0020h
M8259M_ICW2  equ 0021h
M8259M_ICW3  equ 0021h
M8259M_ICW4  equ 0021h
M8259M_OCW1  equ 0021h
M8259M_OCW2  equ 0020h
M8259M_OCW3  equ 0020h
M8259M_IRR   equ 0020h
M8259M_ISR   equ 0020h

M8259S_ICW1  equ 00A0h
M8259S_ICW2  equ 00A1h
M8259S_ICW3  equ 00A1h
M8259S_ICW4  equ 00A1h
M8259S_OCW1  equ 00A1h
M8259S_OCW2  equ 00A0h
M8259S_OCW3  equ 00A0h
M8259S_IRR   equ 00A0h
M8259S_ISR   equ 00A0h


; S2 ========== 数据部分 ==========

; -------- 数据段 --------
data    segment

; 数码管段码表
seg_table   db  3Fh,06h,5Bh,4Fh,66h,6Dh,7Dh,07h     ; 01234567
            db  7Fh,6Fh,77h,7Ch,39h,5Eh,79h,71h     ; 89abcdef
            db  3Dh,00h                             ; g 不显示

; 声音频率表
freq_table  dw      000
            dw      TIM_CLKSRC_FREQ/131
            dw      TIM_CLKSRC_FREQ/147
            dw      TIM_CLKSRC_FREQ/165
            dw      TIM_CLKSRC_FREQ/175
            dw      TIM_CLKSRC_FREQ/196
            dw      TIM_CLKSRC_FREQ/221
            dw      TIM_CLKSRC_FREQ/248
            ;db    000, 262, 294, 330, 350, 393, 441, 495
            ;db    000, 525, 589, 661, 700, 786, 882, 990
            
; 数码管缓存，6位数码管
seg_data    db  6 dup(00h)      
; 显示分配：
;   当前模式（1 演奏模式 2 录音模式 3 播放模式）
;   不显示
;   当前音阶
;   当前音区
;   当前音调
;   不显示


; 数码管刷新周期倒数
seg_refresh_duty_count  db  00h

; 数码管当前位
seg_current_chip        db  00h

; 按键状态位
key_status_current      db  00h
key_status_last         db  00h

; systick时间
systick_time            dw  00h

; 音区存储
; 音调存储
; 音阶存储

data    ends



; -------- 堆栈段 --------
sstack  segment stack
        dw      32 dup(?)
sstack  ends



; S3 ========== 程序部分 ==========

code    segment
        assume cs:code, ss:sstack, ds:data

start:  

; S3.1 -------- 主程序 --------

; 初始化 >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
        call init

; 主循环 >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
FPP:
        
    ; 更新上一按键状态 --------------------------------
        mov     bl, key_status_last
        mov     bh, key_status_current
        mov     bl, bh
        mov     key_status_last, bl

    ; 键盘扫描 ------------------------------------
        call    keyscan
        test    al, FFh
        jz      main_cond_keyscan_nokey

        main_cond_keyscan_pressed:
        ; 保存当前按键状态
        mov     bh, 01h
        mov     key_status_current, bh
        jmp     main_cond_keyscan_end

        main_cond_keyscan_nokey:
        ; 保存当前按键状态
        mov     bh, 00h
        mov     key_status_current, bh
        main_cond_keyscan_end:

    ; 此时 al-按键值 bl-上一按键状态 bh-当前按键状态

    ; 按键事件处理 ----------------------------------

    ; 按键处理程序中，bx可任意更改

        test    bl, 01h
        jnz     main_cond_keyevent_last_pressed:

        main_cond_keyevent_last_nokey:
            test    bh, 01h
            jnz     main_cond_keyevent_last_nokey_current_pressed:
            main_cond_keyevent_last_nokey_current_nokey:
                call    keyevent_handler_idle
                jmp     main_cond_keyevent_last_end

            main_cond_keyevent_last_nokey_current_pressed:
                call    keyevent_handler_pressed
                jmp     main_cond_keyevent_last_end

        main_cond_keyevent_last_pressed:
            test    bh, 01h
            jnz     main_cond_keyevent_last_pressed_current_pressed:
            main_cond_keyevent_last_pressed_current_nokey:
                call    keyevent_handler_released
                jmp     main_cond_keyevent_last_end

            main_cond_keyevent_last_pressed_current_pressed:
                call    keyevent_handler_hold
                jmp     main_cond_keyevent_last_end

        main_cond_keyevent_last_end:

        ; 键盘扫描后续处理
        call    keyscan_next_hook


LPP:    NOP
        jmp    FPP
; S3.2 -------- 子程序 --------

; /////////////////////////////////////////////////////////////

; 系统初始化子程序
init proc
        cli
        call    irq_init
        call    M8254_init
        call    M8255_init
        call    M8259_init
        sti
        ret
init endp

; 中断初始化子程序
; 填写中断向量表
irq_init proc
        push    ax
        push    ds
        push    si

        mov     ax, 0000h
        mov     ds, ax
        mov     ax, offset mir7_handler
        mov     si, 003Ch
        mov     [si], ax
        mov		ax, cs
        mov     si, 003Eh
        mov     [si], ax

        pop     si
        pop     ds
        pop     ax
        ret
irq_init endp


; S3.2.2 ------ 外设库 ------

; /////////////////////////////////////////////////////////////
; S3.2.2.1 定时器外设

; 8254定时器初始化子程序
M8254_init proc
        push    dx
        push    ax

        mov     dx, M8254_CTL        ; 控制端口
        mov     al, 00110100b       ; 计数器0，16位读写，方式2，二进制
        out     dx, al

        mov     al, 01110110b       ; 计数器1，16b，方式3，二进制
        out     dx, al

        mov     dx, M8254_A          ; 计数器0
        mov     ax, SYSTICK_TIM_COUNT ; SYSTICK定时器计数
        out     dx, al              ; 写通道0高低8位计数
        mov     al, ah
        out     dx, al

        pop     ax
        pop     dx
        ret
M8254_init endp

; 8254定时器获取当前计数程序（获取systick）---- （已废弃——不需要的函数）
; 传出：ax 计数值
;M8254_get_channel_0 proc
;        push    dx
;        push    bx

;        mov     dx, M8254_CTL
;        mov     al, 00000100b           ; 通道0，锁存，方式2，二进制
;        out     dx, al

;        mov     dx, M8254_A
;        in      al, dx                  ; 读取通道0
;        mov        bl, al
;        in      al, dx
;        mov        bh, al
;        mov        ax, bx

;        mov     dx, M8254_CTL
;        mov     al, 00110100b           ; 通道0，16位读写，方式2，二进制
;        out     dx, al
    
;        pop        bx
;        pop     dx
;        ret
;M8254_get_channel_0 endp


; /////////////////////////////////////////////////////////////
; S3.2.2.2 并口外设

; 8255并口初始化子程序
M8255_init proc
        push    dx
        push    ax

        mov     dx, M8255_CTL
        mov     al, 10000001b       ; 方式0，A-O, CH-O, B_0, B-O, CL-I
        out     dx, al

        pop     ax
        pop     dx
        ret
M8255_init endp


; /////////////////////////////////////////////////////////////
; S3.2.2.3 中断外设

; 8259中断初始化子程序
M8259_init proc
        push    ax

        ; 初始化主片8259
        mov     al, 00010001b           ; ICW1 边沿触发模式
        out     M8259M_ICW1, al

        mov     al, 00001000b           ; ICW2 
        out     M8259M_ICW2, al

        mov     al, 00000100b           ; ICW3 从片在IR2
        out     M8259M_ICW3, al

        mov     al, 00000001b           ; ICW4 全嵌套，不自动失能
        out     M8259M_ICW4, al

        mov     al, 01111111b           ; 7号SYSTICK
        out     M8259M_OCW1, al

        pop     ax
        ret
M8259_init endp


; S3.2.3 ------ 应用库 ------

; /////////////////////////////////////////////////////////////
; S3.2.3.1 延时程序

; 延时1ms子程序(systick) >>>>>>>>>>>>>>>>>>>>>>>>>>>
;delay_1ms_timer proc
;        push    ax
;        push    bx

;        call    M8254_get_channel_0
;        mov     bx, ax
;        dec     bx 
;delay_1ms_timer_loop_begin:
;        nop
;        call    M8254_get_channel_0
;        sub     ax, bx
;        jnz     delay_1ms_timer_loop_begin
;delay_1ms_timer_loop_end:

;        pop     bx
;        pop     ax
;        ret
;delay_1ms_timer endp

delay_1ms proc

        push    ax
        push    bx

        mov     ax, systick_time
        mov     bx, ax
        inc     bx

delay_1ms_loop_begin:
        mov     ax, systick_time
        sub     ax, bx
        jnz     delay_1ms_loop_begin

        pop     bx
        pop     ax
        ret
delay_1ms endp

; 延时n子程序(systick) >>>>>>>>>>>>>>>>>>>>>>>>>>>>>
; 传入：cx 延时毫秒数
delay proc
delay_loop_begin:
        call    delay_1ms
        loop    delay_loop_begin
delay_loop_end:

        ret
delay endp

; 延时20ms子程序（用于键盘消抖） >>>>>>>>>>>>>>>>>>>>>>>>>>>
delay_20ms proc
        push    cx

        mov     cx, 20
        call    delay

        pop     cx
        ret
delay_20ms endp


; S3.2.4 ------ 模块库 ------

; /////////////////////////////////////////////////////////////
; S3.2.4.1 键盘模块

; 键盘判断按键按下 >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
; 传出：zero标志位
keyscan_get_status proc
        push    ax
        push    dx

        ; 通道A输出低电平
        mov     al, 00h
        mov     dx, M8255_A
        out     dx, al

        ; 通道C读取
        mov     dx, M8255_C
        in      al, dx

        not     al
        and     al, 0Fh

        pop     dx
        pop     ax
        ret
keyscan_get_status endp


; 键盘扫描-获取当前列数据 >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
; 传出：cx 第n行，为0为未扫描到
keyscan_get_column proc
        push    dx
        push    ax

        ; 读取端口C -> AL
        mov     dx, M8255_C
        in      al, dx
        
; 循环检测列扫描输出信号，共循环5次
        mov     cx, 0004h
keyscan_get_column_loop_begin:

        ; 如果cx=0，说明没有扫描到信号，退出循环
        test    cx, 0FFFFh
        jz      keyscan_get_column_loop_end
        ; 否则继续
        shr     al, 1
        jc      keyscan_get_column_loop_end             ; 如果当前为0则退出扫描（已扫描到）
        loop    keyscan_get_column_loop_begin

keyscan_get_column_loop_end:
; 循环结束

        pop     ax
        pop     dx
        ret
keyscan_get_column endp


; 键盘扫描子程序 >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
; 传出：al 按键值
keyscan_get_key proc
        push    bx
        push    cx
        push    dx

; 循环设置端口A输出值，共循环5次
        mov     al, 11101111b           ; 结合循环移位，可产生0111 1011 1101 1110 扫描码
        mov     cx, 0004h
keyscan_get_key_loop_begin:
        test    cx, 0FFFFh
        jz      keyscan_get_key_loop_end    ; 如果CX为0,退出循环

        shr     al, 1
        mov     dx, M8255_A              ; 输出扫描码至A端口
        out     dx, al
        mov     bx, cx                  ; 列扫描子程序需要使用CX传递结果
        call    keyscan_get_column      ; 调用扫描子程序
        test    cx, 0FFFFh
        jnz     keyscan_get_key_loop_end    ; 如果返回值不为0，说明扫描到了，退出循环
        mov     cx, bx                  ; 恢复CX
        loop    keyscan_get_key_loop_begin  ; 否则未扫描到，需要进行下一次循环
keyscan_get_key_loop_end:

; 条件选择：根据CX是否为0判断是否扫描到按键
        test    cx, 0FFFFh
        jz      keyscan_get_key_cond_err    ; CX=0，未扫描到按键
; 成功扫描到按键
        ; 当前 bx=第几列 cx=第几行
        ; 计算按键值=(4-cl)*4+(bl)

        mov     ch, 4
        sub     ch, cl
        shl     ch, 1
        shl     ch, 1
        mov     al, bl
        add     al, ch

        jmp     keyscan_get_key_cond_end

; 未扫描到按键，按键编码=0
keyscan_get_key_cond_err:
        mov     al, 00h
keyscan_get_key_cond_end:

        pop     dx
        pop     cx
        pop     bx
        ret
keyscan_get_key endp


; 键盘扫描 完整程序 >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
keyscan proc
; 判断按键是否被按下
keyscan_cond_ispressed:
        call    keyscan_get_status
        jz      keyscan_cond_ispressed_false        ; 如果无按键按下，退出
; 如果被按下
        ; 延时20ms，再次判断是否按下
        call    delay_20ms
        call    keyscan_get_status
        jz      keyscan_cond_ispressed_false        ; 第二次无按键按下，也退出
    ; 如果第二次也按下（稳态）
        call    keyscan_get_key                     ; 获取按键（存于AL）
        jmp     keyscan_return                      ; 返回
; 如果未按下
keyscan_cond_ispressed_false:
        ; 退出
        mov     al, 00h
        jmp     keyscan_return

keyscan_return:
        ret
keyscan endp

; /////////////////////////////////////////////////////////////
; S3.2.4.2 数码管模块

; 数码管动态刷新显示
seg_display proc
        push    ax
        push    bx
        push    dx

		mov		al, 00h
        mov     dx, M8255_B
        out     dx, al              ; 消隐

        ; 获取当前数码管片选
        mov     al, seg_current_chip
        
        test    al, 11011111b
        jz      seg1_show
        test    al, 11101111b
        jz      seg2_show
        test    al, 11110111b
        jz      seg3_show
        test    al, 11111011b
        jz      seg4_show
        test    al, 11111101b
        jz      seg5_show
        jmp     seg6_show

seg1_show:
        mov     ah, seg_data[0]
        mov     bl, 11101111b
        jmp     seg_display_return
seg2_show:
        mov     ah, seg_data[1]
        mov     bl, 11110111b
        jmp     seg_display_return
seg3_show:
        mov     ah, seg_data[2]
        mov     bl, 11111011b
        jmp     seg_display_return
seg4_show:
        mov     ah, seg_data[3]
        mov     bl, 11111101b
        jmp     seg_display_return
seg5_show:
        mov     ah, seg_data[4]
        mov     bl, 11111110b
        jmp     seg_display_return
seg6_show:
        mov     ah, seg_data[5]
        mov     bl, 11011111b
        
seg_display_return:


        mov     dx, M8255_A
        out     dx, al              ; 片选

        mov     al, ah

        mov     dx, M8255_B
        out     dx, al              ; 显示

        mov     seg_current_chip, bl

        pop     dx
        pop     bx
        pop     ax
        ret
seg_display endp


; /////////////////////////////////////////////////////////////
; S3.2.4.3 蜂鸣器模块

; 蜂鸣器开关
; 8255 PC4->8254 GATE1
beep_enable proc
        push    dx
        push    ax
        
        ; 设置PC4=1
        mov     dx, M8255_C
        mov     al, 010h
        out     dx, al
        
        pop     ax
        pop     dx
        ret
beep_enable endp

beep_disable proc
        push    dx
        push    ax
        
        ; 设置PC4=0
        mov        dx, M8255_C
        mov        al, 00h
        out        dx, al
        
        pop        ax
        pop        dx
        ret
beep_disable endp


; 蜂鸣器频率设置
; 传入：al 音调 ah 音阶
beep_set_tone proc
        push    si
        push    ax
        push    bx
        push    cx
        push    dx
        
        mov        si, ax
        and        si, 00FFh
        mov        bx, freq_table[si]
        
        mov        cl, ah
        shr        bx, cl
        
        ; 定时器值送往8254
        mov        dx, M8254_B
        mov        al, bl
        out        dx, al
        mov        al, bh
        out        dx, al
        
        
        pop        dx
        pop        cx
        pop        bx
        pop        ax
        pop        si
        ret
beep_set_tone endp


; S3.2.5 ------ 按键处理 ------

; 按键按下程序
keyevent_handler_pressed proc
        call    mod_piano_pressed
        call    mod_recorder_pressed
        call    mod_player_pressed
        ret
keyevent_handler_pressed endp

; 按键弹起程序
keyevent_handler_released proc
        call    mod_piano_released
        call    mod_recorder_released
        ret
keyevent_handler_released endp

; 按键保持程序

keyevent_handler_hold proc
        ret
keyevent_handler_hold endp

; 按键空闲程序
keyevent_handler_idle proc
        call    mod_player_pressed
        ret
keyevent_handler_idle endp

; 键盘扫描后续处理
keyscan_next_hook proc
        ; 更新数码管：当前模式
keyscan_next_hook endp


; S3.2.6 ------ 演奏程序 ------

; 演奏程序-按键按下事件hook
mod_piano_pressed proc

    ; 为音调按键

        ; 更新数码管显示

        ; 驱动蜂鸣器发声
        mov     ah, 1
        call    beep_enable

    ; 为音区音阶调节按键

        ; 更新数码管显示

        ret
mod_piano_pressed endp

; 演奏程序-按键弹起事件hook
mod_piano_released proc

        ; 关闭蜂鸣器
        call    beep_disable

        ret
mod_piano_released endp

; 录音程序-按键按下事件hook
mod_recorder_pressed proc

    ; 为音调按键
        ; 计算上一音调弹起延时
            ; 上一音调弹起延时=此时时间-缓存时间

        ; 记录此音阶音区音调
        ; 缓存当前时间

    ; 为录音功能按键

        ret
mod_recorder_pressed endp

; 录音程序-按键弹起事件hook
mod_recorder_released proc
    
    ; 为音调按键

        ; 计算上一音调按下延时

        ; 记录此音调弹起时间

        ret
mod_recorder_released endp

; 播放程序-按键按下事件hook
mod_player_pressed proc

        ; 判断按键是否为播放键

        ; 如果是播放按键
        
            ; 判断当前状态是否为播放状态

            ; 是播放状态

                ; 停止播放（设置状态=演奏）

            ; 不是播放状态

                ; 开始播放（设置状态=播放）

        ; 如果不是播放按键

        ret
mod_player_pressed endp

; 播放程序-按键空闲事件hook
mod_player_idle proc
        ret
mod_player_idle endp

; S3.2.7 ------ 中断处理 ------

; MIR7 中断处理程序
mir7_handler proc
        cli

        pushf
        push    ax

        ; systick处理
        ; systick时钟自增1
        mov     ax, systick_time
        inc     ax
        mov     systick_time, ax

        ; SEG 处理
        mov     al, seg_refresh_duty_count
        inc     al
        cmp     al, SEG_SRV_DUTY            ; 当前=预设分频?
        jz      seg_refresh_duty_cond_true
seg_refresh_duty_cond_false:                ; 不等于，分频计数+1
        inc     al
        mov     seg_refresh_duty_count, al
        jmp     seg_refresh_duty_cond_end
seg_refresh_duty_cond_true:                 ; 等于，刷新显示，重置分频计数
        call    seg_display
        mov     al, 0
        mov     seg_refresh_duty_count, al
seg_refresh_duty_cond_end:

        ; 中断结束
        mov     al, 20h
        out     20h, al

        pop     ax
        popf

        sti
        iret
mir7_handler endp

code    ends
        end start