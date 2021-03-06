;=============================================
; todo: 录音满时需提醒
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
TIM_CLKSRC_FREQ     equ 184320
; Systick频率
SYSTICK_FREQ        equ 500				; 实际上是1kHz

TIM_CLKSRC_TONE_H		equ 02h
TIM_CLKSRC_TONE_L		equ 0D000h

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
seg_table   db  3Fh,06h,5Bh,4Fh,66h,6Dh,7Dh,07h,7Fh,6Fh     ; 0123456789
            db  39h,5Eh,79h,71h,3Dh,77h,7Ch,00h             ; cdefgab不显示

; 声音频率表
freq_table dw 131,147,165,175,196,221,248,262,294,330,371,416,467
;freq_table_m = freq_tablex2
;freq_table_h = freq_tablex4
            
; 数码管缓存，6位数码管
seg_data    db        00h,00h,39h,06h,00h,06h
; 显示分配：
;   当前模式（1 演奏模式 2 录音模式 3 播放模式）
;   不显示
;   当前音调
;   当前音区
;   当前音阶
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

; 上次按键
last_key                db 00h

; 当前音区
current_zone			db	01h		; default: mid
; 当前音调
current_tone			db	00h		; default: C

; 当前模式
current_mode			db	01h
; 01-piano 02-record 03-play

; 数码管使能标志
seg_enable				db	01h

; 录音指针
recorder_head           db 00h
; 录音上次记录按键按下/弹起时间
recorder_last_time      dw 00h
; 录音数据区
recorder_data       dw 210 dup(00h)
;recorder_data dw 0001h,00F00h,00F00h, 0002h,00F00h,00F00h, 0003h,00F00h,0F00h, 0100h,1600h,0000h
recorder_end  		dw 00h
; 播放程序状态
player_status           db 00h
; 00 - need to send beep configurations
; 01 - waiting for first sequence
; 02 - waiting for second sequence

player_head             db 00h
player_last_time        dw 00h

data    ends



; -------- 堆栈段 --------
sstack  segment stack
        dw      32 dup(?)
sstack  ends



; S3 ========== 程序部分 ==========

code    segment
        assume cs:code, ss:sstack, ds:data

start:  

		mov ax, data
		mov ds, ax

; S3.1 -------- 主程序 --------

mov ax, offset recorder_data
; 初始化 >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
        call init

; 主循环 >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
FPP:
        
    ; 更新上一按键状态 --------------------------------
        mov     last_key, al
        mov     bl, key_status_last
        mov     bh, key_status_current
        mov     bl, bh
        mov     key_status_last, bl

    ; 键盘扫描 ------------------------------------
    	call seg_set_enable
		mov cx, 20
		call delay
		call seg_set_disable
        call    keyscan
        test    al, 0FFh
        jz      main_cond_keyscan_nokey

        main_cond_keyscan_pressed:
        ; 保存当前按键状态
        mov     bh, 01h
        mov     key_status_current, bh
        call probe_led_on
        jmp     main_cond_keyscan_end

        main_cond_keyscan_nokey:
        ; 保存当前按键状态
        mov     bh, 00h
        mov     key_status_current, bh
        call probe_led_off
        main_cond_keyscan_end:

    ; 此时 al-按键值 bl-上一按键状态 bh-当前按键状态

    ; 按键事件处理 ----------------------------------

    ; 按键处理程序中，bx可任意更改

        test    bl, 01h
        jnz     main_cond_keyevent_last_pressed

        main_cond_keyevent_last_nokey:
            test    bh, 01h
            jnz     main_cond_keyevent_last_nokey_current_pressed
            main_cond_keyevent_last_nokey_current_nokey:
                call    keyevent_handler_idle
                jmp     main_cond_keyevent_last_end

            main_cond_keyevent_last_nokey_current_pressed:
                call    keyevent_handler_pressed
                jmp     main_cond_keyevent_last_end

        main_cond_keyevent_last_pressed:
            test    bh, 01h
            jnz     main_cond_keyevent_last_pressed_current_pressed
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
        mov key_status_current, 00h
        mov key_status_last, 00h
        mov systick_time, 0
        mov current_zone, 1
        mov current_tone, 0
        mov current_mode, 01
        mov recorder_head, 0
        mov player_head, 0
        mov player_status, 0
        mov seg_data[0], 00h
        mov seg_data[1], 00h
        mov seg_data[2], 39h
        mov seg_data[3], 06h
        mov seg_data[4], 00h
        mov seg_data[5], 06h
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
        jnc      keyscan_get_column_loop_end             ; 如果当前为0则退出扫描（已扫描到）
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
        ; 计算按键值=(cx-1)*4+(5-bx) Not right
        ; (4-cl)*4+(bl)
        
        mov ch, 4
        sub ch, cl
        shl ch, 1
        shl ch, 1
        mov al, bl
        add al, ch

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
		push bx
; 判断按键是否被按下
keyscan_cond_ispressed:
		; 保存端口A状态
		mov dx, M8255_A
		in al, dx
        call    keyscan_get_status
        ; 恢复端口A状态
		mov dx, M8255_A
		out dx, al
        jz      keyscan_cond_ispressed_false        ; 如果无按键按下，退出
; 如果被按下
        ; 延时20ms，再次判断是否按下
        call    delay_20ms
        ; 保存端口A状态
		mov dx, M8255_A
		in al, dx
        call    keyscan_get_status
        ; 恢复端口A状态
		mov dx, M8255_A
		out dx, al
        jz      keyscan_cond_ispressed_false        ; 第二次无按键按下，也退出
    ; 如果第二次也按下（稳态）
    	; 保存端口A状态
		mov dx, M8255_A
		in al, dx
		mov bl, al
        call    keyscan_get_key                     ; 获取按键（存于AL）
        mov ah, al
        ; 恢复端口A状态
        mov al, bl
		mov dx, M8255_A
		out dx, al
		mov al, ah
        jmp     keyscan_return                      ; 返回
; 如果未按下
keyscan_cond_ispressed_false:
        ; 退出
        mov     al, 00h
        jmp     keyscan_return

keyscan_return:
		pop		bx
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
        
        mov al, seg_enable
        cmp al, 1
        jnz seg_display_end

        ; 获取当前数码管片选
        mov     al, seg_current_chip
        
        cmp    al, 00011111b
        jz      seg1_show
        cmp    al, 00101111b
        jz      seg2_show
        cmp    al, 00110111b
        jz      seg3_show
        cmp    al, 00111011b
        jz      seg4_show
        cmp    al, 00111101b
        jz      seg5_show
        jmp     seg6_show

seg1_show:
		mov 	al, 00011111b
        mov     ah, seg_data[0]
        mov     bl, 00101111b
        jmp     seg_display_return
seg2_show:
		mov		al, 00101111b
        mov     ah, seg_data[1]
        mov     bl, 00110111b
        jmp     seg_display_return
seg3_show:
		mov		al, 00110111b
        mov     ah, seg_data[2]
        mov     bl, 00111011b
        jmp     seg_display_return
seg4_show:
		mov		al, 00111011b
        mov     ah, seg_data[3]
        mov     bl, 00111101b
        jmp     seg_display_return
seg5_show:
		mov		al, 00111101b
        mov     ah, seg_data[4]
        mov     bl, 00111110b
        jmp     seg_display_return
seg6_show:
		mov 	al, 00111110b
        mov     ah, seg_data[5]
        mov     bl, 00011111b
        
seg_display_return:


        mov     dx, M8255_A
        out     dx, al              ; 片选

        mov     al, ah

        mov     dx, M8255_B
        out     dx, al              ; 显示

        mov     seg_current_chip, bl

seg_display_end:
        pop     dx
        pop     bx
        pop     ax
        ret
seg_display endp

seg_set_enable proc
		mov seg_enable, 1
		ret
seg_set_enable endp

seg_set_disable proc
		mov	seg_enable, 0
		ret
seg_set_disable endp

seg_display_piano proc
		push si
		push ax
		
		; 模式
		mov si, 1
		mov ah, seg_table[si]
		mov seg_data[5], ah
		
		; 不显示
		mov seg_data[4], 00h
		
		; 音调
		mov al, current_tone
		mov si, ax
		and si, 00FFh
		add si, 10
		mov ah, seg_table[si]
		mov seg_data[3], ah
		
		; 音区
		mov al, current_zone
		mov si, ax
		and si, 00FFh
		mov ah, seg_table[si]
		mov seg_data[2], ah
		
		; 音阶 不显示
		mov seg_data[1], 00h
		
		; 不显示
		mov seg_data[0], 00h
		
		pop ax
		pop si
		ret
seg_display_piano endp

; /////////////////////////////////////////////////////////////
; S3.2.4.3 蜂鸣器模块

; 蜂鸣器开关
; 8255 PC4->8254 GATE1
beep_enable proc
        push    dx
        push    ax
        
        ; 设置PC4=1
        mov dx, M8255_CTL
        mov al, 00001001b
        out dx, al
        
        pop     ax
        pop     dx
        ret
beep_enable endp

beep_disable proc
        push    dx
        push    ax
        
        ; 设置PC4=0
        mov dx, M8255_CTL
        mov al, 00001000b
        out dx, al
        
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
        
        ; 获取频率
        ; al 存放音符
        mov si, ax
        and si, 00FFh
        
        ; ah[3:0] 存放音调
        ; c-0 d-1 e-2 f-3 g-4 a-5 b-6
        mov bl, ah
        and bx, 000Fh
        add si, bx
        shl si, 1
        
        mov bx, freq_table[si]
        
        ; ah[7:4] 存放音区
        ; 低-0 中-1 高-2
        mov cl, ah
        shr cl, 1
        shr cl, 1
        shl bx, cl
        
        ; 计算分频数
        mov dx, TIM_CLKSRC_TONE_H
        mov ax, TIM_CLKSRC_TONE_L
        div bx
        
        mov bx, ax
        
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

probe_led_on proc
        push    dx
        push    ax
        
        ; 设置PC5=1
        mov dx, M8255_CTL
        mov al, 00001011b
        out dx, al
        
        pop        ax
        pop        dx
        ret
probe_led_on endp

probe_led_off proc
        push    dx
        push    ax
        
        ; 设置PC5=0
        mov dx, M8255_CTL
        mov al, 00001010b
        out dx, al
        
        pop        ax
        pop        dx
        ret
probe_led_off endp


; S3.2.5 ------ 按键处理 ------

; 按键按下程序
keyevent_handler_pressed proc
		call	mod_mode_pressed
        call    mod_piano_pressed
        call    mod_recorder_pressed
        call mod_player_pressed
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
        call    mod_player_idle
        ret
keyevent_handler_idle endp

; 键盘扫描后续处理
keyscan_next_hook proc
        ; 更新数码管：当前模式
        ret
keyscan_next_hook endp

; 模式切换处理hook
; 传入： al 按键值
; 传出： al 按键值
mod_mode_pressed proc
		push bx

		mov bl, current_mode
		
	; key 13 record
		cmp al, 13
		jnz mod_mode_pressed_not_13
		
		; current piano target recorder
		cmp bl, 01
		jz mod_mode_to_recorder
		; current recorder target recorder
		cmp bl, 02
		jz mod_mode_to_piano
		; current player target recorder ignored
		jmp mod_mode_pressed_return
		
	mod_mode_pressed_not_13:
	; key 14 play
		cmp al, 14
		jnz mod_mode_pressed_return
		
		; current piano target player
		cmp bl, 01
		jz mod_mode_to_player
		
		; current recorder target player ignored
		cmp bl, 02
		jz mod_mode_pressed_return
		
		; current player target player
		jmp mod_mode_to_piano
		
		
	mod_mode_to_piano:
		; 正在录音，保存录音并退出     ---------------------probe 与下方代码重复，可优化
		
		push dx
		push si
		
		cmp bl, 02
		jnz mod_mode_to_piano_not_recording
		
		; close recording
		mov dl, recorder_head
		; if have no recording data, ignore
		test dl, 0FFh
		jz mod_mode_to_piano_not_recording
		
    	mov si, dx
    	and si, 00FFh
    	mov recorder_data[si], 0
    	mov recorder_head, 0
    	mov recorder_last_time, 0
    	
    	mod_mode_to_piano_not_recording:
    	
    	cmp bl, 03
    	jnz mod_mode_to_piano_not_playing
    	; close playing
    	mov player_head, 0
    	call beep_disable
    	mov player_status, 00h
    	call seg_display_piano
    	
    	mod_mode_to_piano_not_playing:
    	
    	pop si
    	pop dx
    	
		mov bl, 01
		jmp mod_mode_to_end
	mod_mode_to_recorder:
		mov bl, 02
		jmp mod_mode_to_end
	mod_mode_to_player:
		mov bl, 03
		
	mod_mode_to_end:
		mov current_mode, bl
		
		mov si, bx
		and si, 00FFh
		mov ah, seg_table[si]
		mov seg_data[5], ah
		
mod_mode_pressed_return:
		pop bx
		ret
mod_mode_pressed endp

; S3.2.6 ------ 演奏程序 ------

; 演奏程序-按键按下事件hook
; 传入： al 按键值
; 传出： al 按键值 bx 蜂鸣器配置值
mod_piano_pressed proc
        push ax                 ; 保存按键值

		; no response to mode 3(playing)
		mov bl, current_mode
		cmp bl, 03
		jz mod_piano_pressed_return_temp

		; key 0
		cmp al, 00h
		jz mod_piano_pressed_return_temp
	
		; key 1-7
		cmp al, 8
		jc mod_piano_pressed_key_note
		
		; key 9
		cmp al, 9
		jz mod_piano_pressed_key_tone_up
		
		; key 10
		cmp al, 10
		jz mod_piano_pressed_key_tone_down
		
		; key 11
		cmp al, 11
		jz mod_piano_pressed_key_zone_up
		
		; key 12
		cmp al, 12
		jz mod_piano_pressed_key_zone_down_temp
	
	; avoiding jumping too far
	mod_piano_pressed_return_temp:
		jmp mod_piano_pressed_return
	
	; 为音阶按键
	mod_piano_pressed_key_note:

        ; 更新数码管音符区显示
        mov si, ax
        and si, 00FFh
        mov ah, seg_table[si]
        mov seg_data[1], ah

        ; 驱动蜂鸣器发声
        ; current zone
        mov ah, current_zone
        shl ah, 1
        shl ah, 1
        shl ah, 1
        shl ah, 1
        and ah, 0F0h
        mov bl, current_tone
        and bl, 0Fh
        or ah, bl
        
        dec 	al				; convert keycode to freq index
        push ax                 ; 保存蜂鸣器配置
        call beep_set_tone
        call    beep_enable
        pop bx          ; 恢复并传出蜂鸣器配置
        
        jmp mod_piano_pressed_return
        
    ; 为音调调节按键
    mod_piano_pressed_key_tone_up:
    	
    	mov al, current_tone
    	cmp al, 6
    	jz mod_piano_pressed_return
    	inc al
    	mov current_tone, al
    	
    	mov si, ax
    	and si, 00FFh
    	add si, 10
    	mov ah, seg_table[si]
    	mov seg_data[3], ah
    	
    	jmp mod_piano_pressed_return
    	
  	mod_piano_pressed_key_tone_down:
  		
  		mov al, current_tone
    	cmp al, 0
    	jz mod_piano_pressed_return
    	dec al
    	mov current_tone, al
    	
    	mov si, ax
    	and si, 00FFh
    	add si, 10
    	mov ah, seg_table[si]
    	mov seg_data[3], ah
  	
  		jmp mod_piano_pressed_return
  		
  	mod_piano_pressed_key_zone_down_temp:
  		jmp mod_piano_pressed_key_zone_down
  		
  	mod_piano_pressed_key_zone_up:
  	
  		mov al, current_zone
  		cmp al, 2
  		jz mod_piano_pressed_return
  		inc al
  		mov current_zone, al
  		
  		mov si, ax
  		and si, 00FFh
  		mov ah, seg_table[si]
  		mov seg_data[2], ah
  		
  		jmp mod_piano_pressed_return
  		
  	mod_piano_pressed_key_zone_down:
  	
  		mov al, current_zone
  		cmp al, 0
  		jz mod_piano_pressed_return
  		dec al
  		mov current_zone, al
  		
  		mov si, ax
  		and si, 00FFh
  		mov ah, seg_table[si]
  		mov seg_data[2], ah
  		
  		jmp mod_piano_pressed_return

	mod_piano_pressed_return:
        pop ax          ; 恢复并传出按键值
        ret
mod_piano_pressed endp

; 演奏程序-按键弹起事件hook
mod_piano_released proc
        push ax

        ; 仅作用于演奏模式
        ; 或者录音模式
        mov al, current_mode
        cmp al, 01h
        jnz mod_piano_released_not_piano_mode
        jmp mod_piano_continue
        mod_piano_released_not_piano_mode:
        cmp al, 02h
        jnz mod_piano_released_return 
        
	mod_piano_continue:
        ; 仅用作按键1-7弹起
        ; 筛选按键0-7
        mov al, last_key
        cmp al, 8
        jnc mod_piano_released_return

        ; 按键0忽略
        test al, 0FFh
        jz mod_piano_released_return

        ; 关闭蜂鸣器
        call    beep_disable

    mod_piano_released_return:
        pop ax
        ret
mod_piano_released endp

; 录音程序-按键按下事件hook
; 传入：al 按键值 bx 蜂鸣器配置
; 传出：al 按键值
mod_recorder_pressed proc
        push cx
        push dx

    ; 仅作用于录音模式
    mov cl, current_mode
    cmp cl, 02h
    ;jnz mod_recorder_pressed_not_record_mode
    ;jmp mod_recorder_pressed_is_record_mode
    jnz mod_recorder_pressed_return

;mod_recorder_pressed_not_record_mode:

    ; 当用户录音结束，会按下录音功能键，此时模式改变，但此模块仍会收到按键按下的信号
    ; 此时需要判断是否正在录音，如果在录音，需要停止
    ;mov dl, recorder_head
    ;test dl, 0FFh
    ; 未在录音，直接退出
    ;jz mod_recorder_pressed_return
    ; 正在录音，保存录音并退出     ---------------------probe 与下方代码重复，可优化
    ;mod_recorder_pressed_save:
    ;mov si, dx
    ;and si, 00FFh
    ;mov recorder_last_time, 0
    ;mov recorder_data[si], 0
    ;mov recorder_head, 0
    ;jmp mod_recorder_pressed_return

;mod_recorder_pressed_is_record_mode:

    ; 按键1-7
    mov cl, al
    cmp cl, 8
    jnc mod_recorder_pressed_return
    ; （录音模式切换功能由模式切换模块管理，无需检查录音功能键按下情况）

    ; 检查录音指针是否在头部
    mov cl, recorder_head
    mov si, cx
    and si, 00FFh
    test si, 0FFh
    jz mod_recorder_pressed_data_empty
        ; 录音指针不位于头部，需要计算按键空闲时间
        ; 计算按键空闲时间
        mov cx, recorder_last_time
        mov dx, systick_time
        sub dx, cx
        ; 保存空闲时间
        mov recorder_data[si], dx
        add si, 2

        ; 录音指针位于头部，直接保存蜂鸣器配置
    mod_recorder_pressed_data_empty:
    mov recorder_data[si], bx
    ; 录音指针增加2（已保存16位数据）
    add si, 2
    ; 保存录音指针
    mov cx, si
    mov recorder_head, cl

    ; 保存本次时间
    mov dx, systick_time
    mov recorder_last_time, dx

    mod_recorder_pressed_return:
        pop dx
        pop cx
        ret
mod_recorder_pressed endp

; 录音程序-按键弹起事件hook
mod_recorder_released proc
    push ax
    push bx

    ; 仅响应录音模式
    mov ah, current_mode
    cmp ah, 02h
    jnz mod_recorder_released_return

    ; 仅响应按键1-7
    mov al, last_key
    cmp al, 8
    jnc mod_recorder_released_return
    ; 不响应按键0
    test al, 0FFh
    jz mod_recorder_released_return

    ; 防止错误：当录音指针=0,不响应
    mov al, recorder_head
    test al, 0FFh
    jz mod_recorder_released_return

    mov si, ax
    and si, 00FFh

    ; 按下延时
    mov ax, systick_time
    mov bx, recorder_last_time
    ; 保存现在时间
    mov recorder_last_time, ax
    ; 保存延时时间
    sub ax, bx
    mov recorder_data[si], ax
    
    ; 录音指针加2
    add si, 2
    mov ax, si
    mov recorder_head, al

mod_recorder_released_return:
    pop bx
    pop ax
        ret
mod_recorder_released endp

; 播放程序-按键按下事件hook
; 传入：al 按键值
; 传出：al 按键值
mod_player_pressed proc
    push bx

    ; 仅作用于播放模式
    mov bl, current_mode
    cmp bl, 3
    jnz mod_player_pressed_return

    ; 任意按键按下即停止播放
    mov player_head, 00h
    call beep_disable
    mov player_status, 00h

mod_player_pressed_return:
    pop bx
        ret
mod_player_pressed endp

; 播放程序-按键空闲事件hook
mod_player_idle proc
        push ax
        push bx
        push si
    ; 仅作用于播放模式
    mov al, current_mode
    cmp al, 03h
    jnz mod_player_idle_return_temp

    ; 存储si
    mov al, player_head
    mov si, ax
    and si, 00FFh

    ; 获取存储数据
    mov bx, recorder_data[si]

    ; 当前：si 数据指针 bx 数据

    mov al, player_status
    cmp al, 00h
    jz mod_player_idle_send_configuration
    cmp al, 01h
    jz mod_player_idle_wait_tone
    jmp mod_player_idle_wait_next_tone

mod_player_idle_return_temp:
		jmp mod_player_idle_return

mod_player_idle_send_configuration:
    ; 设置并开启蜂鸣器
    mov ax, bx
    call beep_set_tone
    call beep_enable
    
    ; 更新数码管显示
    push si
    ; 音阶
    mov     si, bx
    and     si, 00FFh
    inc     si
    mov     ah, seg_table[si]
    mov     seg_data[1], ah
    ; 音调
    mov     ax, bx
    mov     al, ah
    mov     si, ax
    and     si, 000Fh
    add     si, 10
    mov     ah, seg_table[si]
    mov     seg_data[3], ah
    ; 音区
    mov     ax, bx          ; -------- todo: opt: 代码可精简
    mov     al, ah
    shr     al, 1
    shr     al, 1
    shr     al, 1
    shr     al, 1
    mov     si, ax
    and     si, 000Fh
    mov     ah, seg_table[si]
    mov     seg_data[2], ah
    
    pop si
    
    ; 记录当前时间
    mov ax, systick_time
    mov player_last_time, ax
    ; 设置下一状态
    mov player_status, 01h
    ; 设置播放指针
    add si, 2
    mov ax, si
    mov player_head, al
    jmp mod_player_idle_return

mod_player_idle_wait_tone:
    ; 设置目标时间
    mov ax, player_last_time
    ;push cx
    ;mov cx, bx
    ;call delay
    ;pop cx
    add bx, ax
    ; 是否到达目标时间
    mov ax, systick_time
    cmp bx, ax
    ; 未到达，退出
    jnz mod_player_idle_return
    ; 到达
    ; 关闭蜂鸣器
    call beep_disable
    ; 存储当前时间
    mov player_last_time, ax
    ; 设置播放指针
    add si, 2
    mov ax, si
    mov player_head, al
    ; 设置下一状态
    mov player_status, 02
    jmp mod_player_idle_return

mod_player_idle_wait_next_tone: ;--------------------probe 有重复代码，可优化
    ; 设置目标时间
    mov ax, player_last_time
    
    ; bx=0, exit
    cmp bx, 0000h
    jnz mod_player_idle_bx_not_zero
    mov current_mode, 01h		; back to piano
    mov player_head, 0
    mov player_status, 00h
    call seg_display_piano 		; display piano state
    jmp mod_player_idle_return
    
    mod_player_idle_bx_not_zero:
    ;push cx
    ;mov cx, bx
    ;call delay
    ;pop cx
    add bx, ax
    ; 是否到达目标时间
    mov ax, systick_time
    cmp bx, ax
    ; 未到达，退出
    jnz mod_player_idle_return
    ; 到达
    ; 设置播放指针
    add si, 2
    mov ax, si
    mov player_head, al
    ; 设置下一状态
    mov player_status, 00h
    jmp mod_player_idle_return


mod_player_idle_return:
        pop si
        pop bx
        pop ax
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
        ;mov     al, seg_refresh_duty_count
        ;inc     al
        ;cmp     al, SEG_SRV_DUTY            ; 当前=预设分频?
        ;jz      seg_refresh_duty_cond_true
seg_refresh_duty_cond_false:                ; 不等于，分频计数+1
        ;inc     al
        ;mov     seg_refresh_duty_count, al
        ;jmp     seg_refresh_duty_cond_end
seg_refresh_duty_cond_true:                 ; 等于，刷新显示，重置分频计数
        ;call    seg_display
        ;mov     al, 0
        ;mov     seg_refresh_duty_count, al
seg_refresh_duty_cond_end:

		call seg_display

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
