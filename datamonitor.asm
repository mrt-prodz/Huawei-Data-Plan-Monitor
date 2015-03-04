; =============================================================================
;
; Win32 API - Data Plan Monitor
; -----------------------------
; by Themistokle "mrt-prodz" Benetatos
;
;
; Display a system tray icon and report available traffic from your dataplan by
; making API queries to your Huawei modem.
;
; Setup your data plan inside your Huawei web administration panel:
; http://192.168.1.1/html/statistic.html
;
; The program will fetch the month current download and upload statistics along
; with the monthly data plan and display the usage percentage on the icon.
;
; The value will be refreshed every 5 minutes.
;
; nasm -f win32 datamonitor.asm -o datamonitor.obj
; golink /entry start /mix datamonitor.obj user32.dll kernel32.dll shell32.dll gdi32.dll ws2_32.dll
;
;
; TODO: - context menu to restart connection ?
;       - service version ?
;       - configuration file ?
;
; --------------------
; http://mrt-prodz.com
;
; =============================================================================

; WINDOW IMPORT
EXTERN LoadCursorA
EXTERN RegisterClassExA
EXTERN CreateWindowExA
EXTERN ShowWindow
EXTERN UpdateWindow
EXTERN DestroyWindow
EXTERN GetMessageA
EXTERN TranslateMessage
EXTERN DispatchMessageA
EXTERN PostQuitMessage
EXTERN DefWindowProcA

; SYSTRAY/ICON IMPORT
EXTERN GetDC
EXTERN CreateCompatibleDC
EXTERN CreateCompatibleBitmap
EXTERN SelectObject
EXTERN ReleaseDC
EXTERN CreateSolidBrush
EXTERN FillRect
EXTERN SetBkMode
EXTERN CreateFontA
EXTERN SetTextColor
EXTERN TextOutA
EXTERN CreateIconIndirect
EXTERN DeleteDC
EXTERN DeleteObject
EXTERN Shell_NotifyIconA
EXTERN GetCursorPos
EXTERN CreatePopupMenu
EXTERN AppendMenuA
EXTERN SetForegroundWindow
EXTERN TrackPopupMenu
EXTERN DestroyMenu

; SOCKET IMPORT
EXTERN WSAStartup
EXTERN WSACleanup
EXTERN socket
EXTERN closesocket
EXTERN inet_addr
EXTERN htons
EXTERN connect
EXTERN send
EXTERN recv

; OTHER IMPORT
EXTERN GetModuleHandleA
EXTERN SetTimer
EXTERN ExitProcess

SECTION .text
    global start


; ===============================================
; Main
; ===============================================
start:
    ; create window
    push 0
    call GetModuleHandleA
    mov dword [hInstance], eax

    push ebx
    mov dword ebx, WndClass
    mov dword [ebx   ], 48                   ; cbSize
    mov dword [ebx+4 ], 3                    ; style
    mov dword [ebx+8 ], wnd_proc             ; lpfnWndProc
    mov dword [ebx+12], 0                    ; cbClsExtra
    mov dword [ebx+16], 0                    ; cbWndExtra
    mov dword [ebx+20], hInstance            ; hInstance
    mov dword [ebx+24], 0                    ; hIcon
    push 32512                               ; Cursor
    push 0
    call [LoadCursorA]
    mov dword [ebx+28], eax                  ; hCursor
    mov dword [ebx+32], 1                    ; hbrBackground
    mov dword [ebx+36], 0                    ; lpszMenuName
    mov dword [ebx+40], ClassName            ; lpszClassName
    mov dword [ebx+44], 0                    ; hIconSm
    push ebx
    call [RegisterClassExA]
    pop ebx
   
    push 0                                   ; lpParam
    push dword [hInstance]                   ; hInstance
    push 0                                   ; hMenu
    push 0                                   ; hWndParent
    push 20                                  ; height
    push 50                                  ; width
    push 0x80000000                          ; y = CW_USEDEFAULT
    push 0x80000000                          ; x = CW_USEDEFAULT
    push 0x3                                 ; CS_HREDRAW | CS_VREDRAW
    push AppName                             ; lpWindowName
    push ClassName                           ; lpClassName
    push 0                                   ; dwExStyle = WS_EX_WINDOWEDGE
    call [CreateWindowExA]
    or eax, eax
    jnz short .window_ok
    
    ; error message box if creating the window failed
    push errWindow
    call logerr
    jmp short .quit
    
.window_ok:
    mov dword [hWnd], eax                    ; store hWnd
    push 0                                   ; SW_HIDE
    push eax
    call [ShowWindow]
    push dword [hWnd]
    call [UpdateWindow]

.message_loop:
    push 0
    push 0
    push 0
    push Msg
    call [GetMessageA]
    or eax, eax                              ; if 0 exit.
    jz short .quit
    push Msg
    call [TranslateMessage]
    push Msg
    call [DispatchMessageA]
    jmp short .message_loop

    ; cleanup and quit
.quit:
    push sock
    call [closesocket]                       ; close socket
    call [WSACleanup]                        ; clean up WSA
    push 0
    call [ExitProcess]

; ===============================================
; CALLBACK WindowProcedure(hwnd, message, wParam, lParam)
; ===============================================
wnd_proc:
    push ebp
    mov ebp, esp
    mov eax, dword [ebp+12]                  ; MESSAGE
    cmp eax, 1
    je short .WM_CREATE 
    cmp eax, 2
    je .WM_DESTROY
    cmp eax, WM_SHELLNOTIFY
    je .WM_SHELLNOTIFY
    cmp eax, 273
    je .WM_COMMAND
    cmp eax, 275
    je .WM_TIMER
    
.DEFAULT:
    push dword [ebp+20]
    push dword [ebp+16]
    push dword [ebp+12]
    push dword [ebp+8]
    call [DefWindowProcA]
    jmp .window_finish
   
.WM_CREATE:
    push esi
    mov dword esi, [ebp+8]                   ; 1st argument - hWnd
    push 0
    push esi                                 ; hWnd
    call create_icon                         ; create dynamic icon with value
    or eax, eax
    jz .window_finish

    mov dword edx, nid
    mov dword [edx], 488                     ; cbSize
    mov dword [edx+4], esi                   ; hWnd
    mov dword [edx+8], 1                     ; uID
    mov dword [edx+12], 23                   ; uFlags - NIF_ICON | NIF_MESSAGE | NIF_TIP | NIF_INFO
    mov dword [edx+16], WM_SHELLNOTIFY       ; uCallbackMessage
    mov dword [edx+20], eax                  ; hIcon
    push edx                                 ; lpdata
    push 0                                   ; dwMessage - NIM_ADD
    call [Shell_NotifyIconA]

    push 0
    push timerInterval
    push IDT_UPDATE
    push esi
    call [SetTimer]
    pop esi
    
    call socket_setup                        ; setup socket
    or eax, eax
    jz short .window_finish
    call update_dataplan                     ; update dataplan
    jmp short .window_finish

.WM_COMMAND:
    mov eax, dword [ebp+16]                  ; wParam
    cmp eax, ID_TRAY_EXIT
    je short .ID_TRAY_EXIT
    jmp .DEFAULT

    .ID_TRAY_EXIT:
        mov eax, dword [ebp+8]               ; hWnd
        push eax
        call [DestroyWindow]
        jmp short .window_finish
    
.WM_SHELLNOTIFY:
    mov eax, dword [ebp+20]                  ; lParam
    cmp eax, 123                             ; WM_CONTEXTMENU
    je short .CONTEXT
    cmp eax, 514                             ; WM_LBUTTONUP
    je short .CONTEXT
    cmp eax, 517                             ; WM_RBUTTONUP
    je short .CONTEXT
    jmp .window_finish
        
    .CONTEXT:
        mov eax, dword [ebp+8]               ; hwnd
        push eax
        call show_context_menu
        jmp short .window_finish

.WM_TIMER:
    mov eax, dword [ebp+16]                  ; wParam
    cmp eax, IDT_UPDATE                      ;
    je short .IDT_UPDATE
    jmp short .window_finish
        
    .IDT_UPDATE:
        call update_dataplan
        jmp short .window_finish
    
.WM_DESTROY:
    push nid                                 ; delete icon from system tray
    push 2                                   ; NIM_DELETE
    call [Shell_NotifyIconA]
    
    push 0
    call [PostQuitMessage]
    xor eax, eax

.window_finish:
    mov esp, ebp
    pop ebp
    retn 16

; ===============================================
; create icon
; -----------
; create_icon(hwnd, value)
; return eax 0 if failed
; ===============================================
create_icon:
    push ebx
    push esi
    push edi
    mov dword edi, [esp+20]                  ; value

    push dword [hWnd]
    call [GetDC]
    or eax, eax
    jz .failed

    mov esi, eax                             ; store hdc in esi
    push esi                                 ; hdc
    call [CreateCompatibleDC]
    or eax, eax
    jz .failed

    mov ebx, eax                             ; store hgdiobj in ebx
    push 16                                  ; height
    push 16                                  ; nWidth
    push esi                                 ; hdc
    call [CreateCompatibleBitmap]
    or eax, eax
    jz .failed

    push eax                                 ; save hBitmap on stack
    push eax                                 ; hBitmap
    push ebx                                 ; hgdiobj
    call [SelectObject]
    or eax, eax
    jz .failed

    push esi                                 ; hdc
    push dword [hWnd]
    call [ReleaseDC]
    or eax, eax
    jz .failed

    ; change color depending on value
    ; 0% green - 30% yellow - 60% orange - 90% red
    cmp edi, 90                              ; percentage value
    jge short .red
    cmp edi, 60
    jge short .orange
    cmp edi, 30
    jge short .yellow
.green:
    push 0x0000FF00
    jmp short .create_brush
.yellow:
    push 0x0000FFFF
    jmp short .create_brush
.orange:
    push 0x000099FF
    jmp short .create_brush
.red:
    push 0x000000FF
.create_brush:
    call [CreateSolidBrush]
    or eax, eax
    jz .failed

    push eax                                 ; store brush on stack for removal
    push 16                                  ; right
    push 16                                  ; bottom
    push 0                                   ; left
    push 0                                   ; top
    push eax                                 ; COLOR_BACKGROUND
    lea dword edx, [esp+4]
    push edx                                 ; RECT on stack
    push ebx                                 ; hgdiobj
    call [FillRect]
    add esp, 16                              ; restore stack (-sizeof(RECT))
    or eax, eax
    jz .failed

    call [DeleteObject]                      ; delete brush on stack
    or eax, eax
    jz .failed
    
    push TRAY_FONT                           ; lpszFace
    push 0                                   ; fdwPitchAndFamily
    push 0                                   ; fdwQuality
    push 0                                   ; fdwClipPrecision
    push 0                                   ; fdwOutputPrecision
    push 0                                   ; fdwCharSet
    push 0                                   ; fdwStrikeOut
    push 0                                   ; fdwUnderline
    push 0                                   ; fdwItalic
    push 100                                 ; fnWeight - FW_THIN
    push 0                                   ; nOrientation
    push 0                                   ; nEscapement
    push TRAY_FONT_W                         ; nWidth
    push TRAY_FONT_H                         ; nHeight
    call [CreateFontA]
    or eax, eax
    jz .failed

    push eax                                 ; hFont
    push ebx                                 ; hgdiobj
    call [SelectObject]
    or eax, eax
    jz .failed

    push eax                                 ; store hFont on stack for later
    push 1                                   ; TRANSPARENT
    push ebx                                 ; hgdiobj
    call [SetBkMode]
    or eax, eax
    jz .failed

    push 0                                   ; crColor
    push ebx                                 ; hgdiobj
    call [SetTextColor]
    or eax, eax
    js .failed                               ; CS_INVALID 0xffffffff

    ; update system tray icon with percentage
    mov eax, edi
    cmp eax, 100                             ; if above or equal 100 dataplan is full (no more traffic available)
    jge short .dataplan_full
    mov dword [usagePercentage], 0           ; reset usagePercentage
    push ebx                                 ; save ebx
    xor ecx, ecx
    mov ebx, 10                              ; divide by 10 to get remainder
.dataplan_to_string:
    rcl ecx, 8                               ; shift left 1 byte to store next value in order
    xor edx, edx                             ; reset remainder
    div ebx                                  ; divide by 10
    add edx, 0x30                            ; add 0x30 to remainder (numbers starts from 0x30)
    add cl, dl                               ; store number
    or eax, eax                              ; no more number?
    jnz short .dataplan_to_string
    mov dword [usagePercentage], ecx         ; store final number as string
    pop ebx                                  ; restore ebx
    jmp short .dataplan_done
.dataplan_full:
    mov dword [usagePercentage], 0x303031
.dataplan_done:
    push usagePercentage
    call strlen

    ; center text in icon
    mov ecx, eax                             ; copy count of length in ecx
    imul ecx, TRAY_FONT_W                    ; length * char_width
    sar ecx, 1                               ; / 2
    mov edx, 8                               ; - half of the icon width
    sub edx, ecx

    push eax                                 ; number of characters
    push usagePercentage                     ; string value
    push 2                                   ; ypos
    push edx                                 ; xpos
    push ebx                                 ; hgdiobj
    call [TextOutA]
    or eax, eax
    jz .failed

    lea dword eax, [esp+4]
    push dword [eax]                         ; hbmColor
    push dword [eax]                         ; hbmMask
    push 0                                   ; yHotspot
    push 0                                   ; xHotspot
    push 1                                   ; fIcon
    lea dword eax, [esp]                     ; load icon info from stack
    push eax                                 ; piconinfo
    call [CreateIconIndirect]
    add esp, 20                              ; restore stack (-sizeof(HICON))
    or eax, eax
    jz .failed

    xchg eax, edi                            ; store icon in edi
    ;--- ---                                 ; esp already points to hFont on stack
    push ebx                                 ; hgdiobj
    call [SelectObject]
    push eax
    call [DeleteObject]
    push ebx                                 ; hgdiobj
    call [DeleteDC]
    push esi                                 ; hdc
    call [DeleteDC]
    call [DeleteObject]                      ; esp points already to hBitmap on stack

    xchg eax, edi                            ; eax should return icon, swap back
    jmp short .return
.failed:
    xor eax, eax
.return:
    pop edi
    pop esi
    pop ebx
    retn 8
    
; ===============================================
; show context menu
; -----------------
; show_context_menu(hwnd)
; return eax 0 if failed
; ===============================================
show_context_menu:
    push ebx
    push esi
    push edi
    mov dword esi, [esp+16]                  ; hwnd - 1st argument
    sub esp, 16                              ; allocate memory for POINT
    lea dword ebx, [esp]
    push ebx                                 ; POINT
    call [GetCursorPos]
    or eax, eax
    jz short .return

    call [CreatePopupMenu]
    or eax, eax
    jz short .return

    mov edi, eax                             ; MENU in edi
    push TXT_TRAY_EXIT
    push ID_TRAY_EXIT
    push 0
    push edi                                 ; MENU
    call [AppendMenuA]
    or eax, eax
    jz short .return

    push esi
    call [SetForegroundWindow]
    push esi                                 ;
    push 0                                   ;
    push dword [ebx+4]                       ; POINT y
    push dword [ebx]                         ; POINT x
    push 32                                  ; TPM_BOTTOMALIGN
    push edi                                 ; MENU
    call [TrackPopupMenu]
    push edi
    call [DestroyMenu]
    
.return:
    add esp, 16
    pop edi
    pop esi
    pop ebx
    retn 4

; ===============================================
; update dataplan
; ------------
; return eax 0 if failed
; ===============================================
update_dataplan:
    ; get used dataplan percentage
    call get_dataplan_percentage
    cmp eax, 0                               ; if below zero we had an error
    jge short .dataplan_ok
.dataplan_error:
    ; get dataplan failed, try re-connecting and get dataplan later
    push sock
    call [closesocket]                       ; close socket
    call [WSACleanup]                        ; clean up WSA
    call socket_setup                        ; setup socket again
    jmp short .error
.dataplan_ok:
    ; update system tray icon with percentage in eax
    mov dword [dataplanUsage], eax
    push eax                                 ; percentage
    push hWnd                                ; hWnd
    call create_icon                         ; create dynamic icon with value
    or eax, eax
    jz short .error

    mov dword [nid+20], eax                  ; hIcon
    push nid                                 ; lpdata
    push 1                                   ; dwMessage - NIM_MODIFY
    call [Shell_NotifyIconA]
    jmp short .return
.error:
    xor eax, eax
.return:
    retn

; ===============================================
; get dataplan percentage
; -----------------------
; return eax percentage | -1 failed
; ===============================================
get_dataplan_percentage:
    push ebx
    ; make get request to retrieve current traffic
    push 1024                                ; buffer size
    push bufferReply                         ; buffer
    push getMonthStats                       ; GET request
    call get_request
    test eax, eax
    jnz short .get_traffic_data_ok
    push errGetRequest
    call logerr
    jmp .failed
.get_traffic_data_ok:

    ; get current download traffic xml data
    push 256                                 ; buffer size for value
    push xmlValue                            ; buffer to store header field value
    push xmlCurrentDownload                  ; header field we want the value from
    push bufferReply                         ; buffer with reply from server
    call get_xml_tag
    or eax, eax
    jz .failed

    ; update tooltip with downloaded bytes value
    mov byte [nid+24], 0                     ; erase earlier tooltip string
    push 64                                  ; buffer size
    lea dword ecx, [nid+24]
    push ecx                                 ; buffer
    push toolTipD                            ; field - Down:
    call strcat                              ;
    
    push 64                                  ; buffer size
    lea dword ecx, [nid+24]
    push ecx                                 ; buffer
    push xmlValue                            ; current download traffic value
    call strcat                              ;
    
    push xmlValue                            ; get number of characters of value
    call strlen
    cmp eax, 6                               ; if not bigger than 6 show bytes
    jnge .show_download_bytes
    
    ; convert bytes to MB - strip 6 bytes from string
    lea dword ecx, [nid+24]
    push ecx                                 ; get number of characters full string
    call strlen
    sub eax, 6                               ; strip 6 bytes
    mov byte [nid+eax+24], 0                 ; limit to MB output
    push toolTipMB                           ; data size
    jmp .download_display
    
.show_download_bytes:
    push toolTipB                            ; data size
    
.download_display:
    pop eax
    push 64                                  ; buffer size
    lea dword ecx, [nid+24]
    push ecx                                 ; buffer
    push eax                                 ; data size
    call strcat                              ;

    ; convert to number
    push xmlValue
    call strtoll
    ; push value on the stack
    push eax                                 ; store low on stack
    push edx                                 ; store high on stack
    ; get current upload traffic xml data
    push 256                                 ; buffer size for value
    push xmlValue                            ; buffer to store xml tag value
    push xmlCurrentUpload                    ; tag we want the value from
    push bufferReply                         ; buffer with reply from server
    call get_xml_tag
    or eax, eax
    jnz .get_upload_ok
    add esp, 8
    jmp .failed
    
.get_upload_ok:
    ; update tooltip with uploaded bytes value
    push 64                                  ; buffer size
    lea dword ecx, [nid+24]
    push ecx                                 ; buffer
    push toolTipU                            ; field - Up:
    call strcat                              ;
    
    push 64                                  ; buffer size
    lea dword ecx, [nid+24]
    push ecx                                 ; buffer
    push xmlValue                            ; current upload traffic value
    call strcat                              ;
    
    push xmlValue                            ; get number of characters of value
    call strlen
    cmp eax, 6                               ; if not bigger than 6 show bytes
    jnge .show_upload_bytes
    
    ; convert bytes to MB - strip 6 bytes from string
    lea dword ecx, [nid+24]
    push ecx                                 ; get number of characters full string
    call strlen
    sub eax, 6                               ; strip 6 bytes
    mov byte [nid+eax+24], 0                 ; limit to MB output
    push toolTipMB                           ; data size
    jmp .upload_display
    
.show_upload_bytes:
    push toolTipB                            ; data size
    
.upload_display:
    pop eax
    push 64                                  ; buffer size
    lea dword ecx, [nid+24]
    push ecx                                 ; buffer
    push eax                                 ; data size
    call strcat                              ;

    ; convert to number
    push xmlValue
    call strtoll
    ; add current upload to current download on the stack
    add dword [esp+4], eax                   ; low
    adc dword [esp], edx                     ; high
    
    ; make get request to retrieve data plan limit
    push 1024                                ; buffer size
    push bufferReply                         ; buffer
    push getStartDate                        ; GET request
    call get_request
    test eax, eax
    jnz short .get_data_plan_ok
    push errGetRequest
    call logerr
    add esp, 8
    jmp .failed
.get_data_plan_ok:
    
    ; get current download traffic xml data
    push 256                                 ; buffer size for value
    push xmlValue                            ; buffer to store xml tag value
    push xmlDataLimit                        ; tag we want the value from
    push bufferReply                         ; buffer with reply from server
    call get_xml_tag
    or eax, eax
    jnz short .dataplan_ok
    add esp, 8
    jmp .failed
    
.dataplan_ok:
    ; update tooltip with data plan value
    push 64                                  ; buffer size
    lea dword ecx, [nid+24]
    push ecx                                 ; buffer
    push toolTipPlan                         ; string to concatenate
    call strcat                              ;
    push 64                                  ; buffer size
    lea dword ecx, [nid+24]
    push ecx                                 ; buffer
    push xmlValue                            ; string to concatenate
    call strcat                              ;
    
    ; dataplan always ends with MB or GB to specify size
    push xmlValue
    call strlen
    cmp word [xmlValue+eax-2], 0x4247        ; last 2 characters are GB ?
    je short .dataplan_gb
    ; if 2 last characters are MB do not add 0
    xor ecx, ecx
    jmp short .convert_dataplan
.dataplan_gb:
    ; if 2 last characters are GB add three 0
    mov ecx, 3
    ; convert to number
.convert_dataplan:
    ; strip last 2 characters and add 0
    push edi
    xchg edx, eax
    mov al, 0x30                             ; set character 0 in al
    mov edi, xmlValue                        ; xmlValue is destination
    add edi, edx                             ; value + length
    sub edi, 2                               ; -2 characters to get at the position of MB or GB
    repne stosb                              ; overwrite bytes with 0
    mov byte [edi], 0                        ; null byte to properly end the string
    pop edi
    ; calculate percentage
    xor eax, eax                             ; reset low
    xor edx, edx                             ; reset high
    push xmlValue                            ; convert xmlValue to number
    call strtoll
    ; check that dataplan is not 0
    or eax, eax                              ; is low equal 0 ?
    jnz short .dataplan_not_zero
    or edx, edx                              ; is high equal 0 as well ?
    jnz short .dataplan_not_zero
    jmp short .dataplan_zero; we can't divide by zero
.dataplan_not_zero:
    ; store dataplan value
    push eax
    push edx
    ; calculate percentage of traffic consumed
    ; ([esp+8][esp+16]/[esp][esp+4]) * 100
    ; strip number from the right to avoid dealing with huge numbers
    ; mov ebx, 1000000
    ; since we eventually multiply by 100 to get a percentage remove two 0
    mov ebx, 10000
    xor edx, edx
    mov dword eax, [esp+8]                   ; high total bytes
    div ebx
    mov dword eax, [esp+12]                  ; low total bytes
    div ebx
    ; divided total bytes by datalimit
    xor edx, edx
    xchg ebx, eax                            ; store temporary eax in ebx
    mov dword eax, [esp+4]                   ; datalimit low
    xchg eax, ebx                            ; switch back total and datalimit
    idiv ebx                                 ; total/datalimit
    ; ...
    add esp, 16                              ; restore stack
    jmp short .return
.dataplan_zero:
    add esp, 16                              ; restore stack
.failed:
    xor eax, eax
    dec eax
.return:
    pop ebx
    retn

; ===============================================
; socket setup
; ------------
; return eax 0 if failed
; ===============================================
socket_setup:
    ; initialize wsadata
    push dword WSADATA
    push 0x202                               ; version 2,2
    call [WSAStartup]                        ; initialize wsadata
    test eax, eax
    jz short .init_ok
    push errWinsock
    jmp .error
.init_ok:

    ; create socket
    push 0                                   ; NULL
    push 1                                   ; SOCK_STREAM
    push 2                                   ; AF_INET
    call [socket]                            ; create socket
    test eax, eax
    jnz short .sock_ok
    push errSocket
    jmp .error
.sock_ok:
    mov dword [sock], eax

    ; connect to server
    push port
    push ip
    call connect_server
    test eax, eax
    jnz short .connect_ok
    push errServer
    jmp .error
.error:
    call logerr                              ; error message is on stack already
    xor eax, eax
    jmp short .return
.connect_ok:
    mov eax, 1
.return:
    retn
    
; ===============================================
; connect server
; -------------
; connect_server(ip, port)
; return eax 1 success | 0 failed
; ===============================================
connect_server:
    push ebx
    mov dword ebx, sockAddr
    ; set socket ip
    mov eax, [esp+8]
    push eax
    call [inet_addr]
    mov dword [ebx+4], eax                   ; sin_addr
    ; set socket port
    mov eax, [esp+12]
    push eax
    call [htons]
    mov word [ebx+2], ax                     ; sin_port
    mov word [ebx], 2                        ; sin_family - AF_INET
    ; connect to server
    push 24                                  ; sockAddr struc size
    push ebx                                 ; sockAddr struc
    push dword [sock]
    call [connect]
    pop ebx
    test eax, eax
    jz short .good
    xor eax, eax
    jmp short .return
.good:
    inc eax
.return:
    retn 8

; ===============================================
; get request
; -----------
; get_request(request, buffer, buffer_size)
; return eax 1 success | 0 failed
; return server reply in buffer
; ===============================================
get_request:
    push ebx
    push esi
    push edi
    mov dword eax, [esp+16]                  ; arg1 - request
    mov dword edi, [esp+20]                  ; arg2 - buffer
    mov dword ebx, [esp+24]                  ; arg3 - buffer size
    ; clear buffer
    mov byte [edi], 0                        ; set first byte to null (in case we already have data)
    ; prepare send request
    mov esi, esp                             ; save stack pointer in esi
    push getMethod                           ; GET method
    push eax                                 ; send request
    push httpVerHost                         ; part 1 - version and host
    push ip                                  ; ip
    push httpUAAccept                        ; part 2 - user agent / accept
    mov ecx, 5                               ; 5 strings to concatenate
.make_request_loop:
    sub esi, 4                               ; origin stack pointer - 4 = next string
    push ecx                                 ; save counter
    push ebx                                 ; buffer size
    push edi                                 ; buffer
    push dword [esi]                         ; string to concatenate
    call strcat                              ;
    pop ecx                                  ; restore counter
    dec ecx                                  ; decrement counter
    or ecx, ecx                              ; counter reached 0 ?
    jne short .make_request_loop
    add esp, 20                              ; restore stack pointer (5 * push dword)
    ; full request is now stored in edi
    push edi                                 ; buffer
    call strlen                              ; get length of request in buffer
    ; make request with concatenated string in bufferReq
    push 0                                   ; flags
    push eax                                 ; len
    push edi                                 ; specify buffer to store string in
    push dword [sock]                        ; SOCKET s
    call [send]                              ; send request
    test eax, eax
    jz .return
    mov byte [edi], 0                        ; use the same buffer to store reply
    xor esi, esi                             ; clear total bytes received
    xor ecx, ecx                             ; we will store Content-Length in ecx
.loop:
    push ecx                                 ; save Content-Length register
    push dword 0
    push ebx
    push edi
    push dword [sock]
    call [recv]                              ; receive reply
    pop ecx                                  ; restore Content-Length register
    test eax, eax
    js short .socket_error
    mov byte [edi+eax], 0                    ; make sure string is null terminated
    jnz short .goodrecv
    jz short .connection_closed
.goodrecv:
    cmp eax, ecx                             ; if Content-Length equal received bytes return
    je short .return
    add esi, eax                             ; update total bytes received with eax
    cmp esi, ebx                             ; check for buffer overflow
    jg short .overflow
    add edi, esi                             ; next chunk of reply is at edi + esi (offset)
    or ecx, ecx
    je short .getlength
    cmp ecx, esi                             ; if total bytes greater or equal than Content-Length return
    jge short .return
.getlength:
    mov eax, edi                             ; copy reply in eax
    sub eax, esi                             ; set pointer at the start of the reply string
    push 128                                 ; buffer size for value
    push headerValue                         ; buffer to store header field value
    push httpContentLength                   ; header field we want the value from
    push eax                                 ; buffer with reply from server
    call get_header_field
    ; convert header field value to number and store into ecx
    or eax, eax
    ;je short .loop <--- will keep on looping if header field is missing
    je short .connection_closed
    push headerValue                         ; convert Content-Length string to number
    call strtoll
    mov ecx, eax                             ; save Content-Length in ecx
    jmp short .loop
.socket_error:
    push errReply
    call logerr
    xor eax, eax
    jmp short .return
.connection_closed:
    push edi
    call strlen
    jmp short .return
.overflow:
    push errReplyOverflow
    call logerr
    xor eax, eax
.return:
    pop edi
    pop esi
    pop ebx
    retn 12

; ===============================================
; get header field
; ----------------
; get_header_field(server_reply, header_field, buffer, buffer_size)
; return eax 0 failed
; ===============================================
get_header_field:
    push esi
    push edi
    push ebx
    mov edi, [esp+16]                        ; server reply
    mov esi, [esp+20]                        ; string to match
    push esi                                 ; get length of string to match
    call strlen
    mov ebx, eax                             ; store a copy of length of string to match for later
    push edi                                 ; get length of server reply
    call strlen
    mov ecx, eax                             ; counter is length of server reply
.loop:
    ; check if first character matches
    mov byte al, [esi]                       ; store first character in al
    inc ecx                                  ; next char
    repnz scasb                              ; look for matching character
    jnz short .nomatch                       ; return if no match
    ; check if last character matches
    xor eax, eax
    mov edx, eax
    mov al, [edi+ebx-2]                      ; is server reply + string to match length the same
    mov dl, [esi+ebx-1]                      ; as last character of string to match?
    cmp al, dl
    jne short .loop
    ; last check for full string match
    push ecx                                 ; store counter in case we need to get back to the loop
    push esi                                 ; store pointer to string to match as well
    push edi                                 ; and server reply pointer too
    inc esi
    mov ecx, ebx                             ; counter is string to match length
    dec ecx
    repz cmpsb                               ; compare string to match with server reply
    pop edi                                  ; restore reply
    pop esi                                  ; restore string to match
    add edi, ebx                             ; offset server reply + checked bytes
    dec edi
    or ecx, ecx                              ; if ecx is 0 we have match
    jz short .match
    sub edi, 2
    pop ecx                                  ; restore counter and keep on looping
    jmp short .loop
.match:    
    ; it's a match
    pop ecx
    push edi                                 ; get length of remaining server reply
    call strlen
    mov ecx, eax                             ; count is for the remaining string
    dec ecx
    cmp word [edi], 0x203A                   ; whitespace and semi-colon always follow header field
    jne short .loop                          ; no match keep looping
    add edi, 2                               ; since we matched 0x203A increment 2 bytes
    xor ecx, ecx                             ; we get a match, retrieve value until \r\n and save in buffer
.count:
    inc ecx                                  ; increment counter until we get a match
    cmp word [edi+ecx], 0x0A0D               ; is \r\n at string + counter?
    jne short .count                         ; look for matching character
    cmp ecx, [esp+28]                        ; we can't write more bytes than buffer size
    jb short .good                           ; above or equal is an overflow, strip remaining
    mov dword ecx, [esp+28]                  ; limit to buffer size
.good:    
    mov esi, [esp+24]                        ; buffer to store value from field
    xchg esi, edi                            ; switch source/destination
    repz movsb                               ; copy bytes to value buffer until ecx = 0
    mov byte [edi+1], 0
    jmp short .return
.nomatch:
    xor eax, eax
    mov dword edi, [esp+24]
    mov dword ecx, [esp+28]
    repnz stosb
.return:
    pop ebx
    pop edi
    pop esi
    retn 16

; ===============================================
; get xml tag
; -----------
; get_xml_tag(server_reply, xml_tag, buffer, buffer_size)
; return eax 0 failed
; ===============================================
get_xml_tag:
    push esi
    push edi
    push ebx
    mov edi, [esp+16]                        ; server reply
    mov esi, [esp+20]                        ; string to match
    push esi                                 ; get length of string to match
    call strlen
    mov ebx, eax                             ; store a copy of length of string to match for later
    push edi                                 ; get length of server reply
    call strlen
    mov ecx, eax                             ; counter is length of server reply
.loop:
    ; check if first character matches
    mov byte al, [esi]                       ; store first character in al
    inc ecx                                  ; next char
    repnz scasb                              ; look for matching character
    jnz short .nomatch                       ; return if no match
    ; check if last character matches
    xor eax, eax
    mov edx, eax
    mov al, [edi+ebx-2]                      ; is server reply + string to match length the same
    mov dl, [esi+ebx-1]                      ; as last character of string to match?
    cmp al, dl
    jne short .loop
    ; last check for full string match
    push ecx                                 ; store counter in case we need to get back to the loop
    push esi                                 ; store pointer to string to match as well
    push edi                                 ; and server reply pointer too
    inc esi
    mov ecx, ebx                             ; counter is string to match length
    dec ecx
    repz cmpsb                               ; compare string to match with server reply
    pop edi                                  ; restore reply
    pop esi                                  ; restore string to match
    add edi, ebx                             ; offset server reply + checked bytes
    dec edi
    or ecx, ecx                              ; if ecx is 0 we have match
    jz short .match
    sub edi, 3
    pop ecx                                  ; restore counter and keep on looping
    jmp short .loop
.match:    
    ; it's a match
    pop ecx
    push edi                                 ; get length of remaining server reply
    call strlen
    mov ecx, eax                             ; count is for the remaining string
    dec ecx
    cmp byte [edi], 0x3E                     ; xml tag ends with >
    jne short .loop                          ; no match keep looping
    inc edi                                  ; since we matched 0x3E increment 1 bytes
    xor ecx, ecx                             ; we get a match, retrieve value until \r\n and save in buffer
.count:
    inc ecx                                  ; increment counter until we get a match
    cmp word [edi+ecx], 0x2F3C               ; is </ at string + counter?
    jne short .count                         ; look for matching character
    cmp ecx, [esp+28]                        ; we can't write more bytes than buffer size
    jb short .good                           ; above or equal is an overflow, strip remaining
    mov dword ecx, [esp+28]                  ; limit to buffer size
.good:    
    mov esi, [esp+24]                        ; buffer to store value from tag
    xchg esi, edi                            ; switch source/destination
    repz movsb                               ; copy bytes to value buffer until ecx = 0
    mov byte [edi], 0
    jmp short .return
.nomatch:
    xor eax, eax
    mov dword edi, [esp+24]
    mov dword ecx, [esp+28]
    repnz stosb
.return:
    pop ebx
    pop edi
    pop esi
    retn 16

; ===============================================
; logerr - log error
; ------------------
; logerr(string)
; ===============================================
logerr:
    mov edx, [esp+4]                         ; set string in edx
    push 0
    push edx
    call logstr
    retn 4

; ===============================================
; log - log message without type
; ------------------------------
; log(string)
; ===============================================
log:
    mov edx, [esp+4]                         ; set string in edx
    push 1
    push edx
    call logstr
    retn 4

; ===============================================
; logstr - log string with type
; -----------------------------
; logstr(string, type)
;
; type: 0 - error
;       1 - message
;
; ===============================================
logstr:
    push esi
    push edi
    push ebx
    mov esi, [esp+16]                        ; set string in esi
    push esi                                 ; get string length
    call strlen
    ; try and get Content-Length from edi
    mov dword eax, [esp+20]                  ; message type
    or eax, eax                              ; if 0 it's a message, else it's an error
    jnz short .msg
    push 3
    push err
    jmp short .display_msg

.msg:
    push 1
    push info
    jmp short .display_msg

.display_msg:
    ; full request is now stored in edi
    push esi
    call strlen
    xchg ecx, eax
    mov esi, edx
    lea dword edi, [nid+160]
    repne movsb
    mov byte [edi], 0                        ; properly end string with null byte

    pop esi
    ; title
    push esi
    call strlen
    xchg ecx, eax
    lea dword edi, [nid+420]
    repne movsb
    mov byte [edi], 0                        ; properly end string with null byte

    pop eax
    mov dword [nid+484], eax                 ; dwInfoFlags - NIIF_INFO
    push nid                                 ; lpdata
    push 1                                   ; dwMessage - NIM_MODIFY
    call [Shell_NotifyIconA]

	; clean balloon tooltip
    lea dword edx, [nid]
    mov dword [edx+12], 23                   ; uFlags - NIF_ICON | NIF_MESSAGE | NIF_TIP | NIF_INFO
    mov byte [edx+160], 0                    ; clear balloon message string
    mov byte [edx+420], 0                    ; clear balloon title string
    
.return:
    pop ebx
    pop edi
    pop esi
    ret 8
    
; ===============================================
; strlen - return length of string
; --------------------------------
; strlen(string)
; return length in eax
; ===============================================
strlen:
    mov ecx, [esp+4]                         ; address of string in ecx
    xor eax, eax                             ; reset counter
.lenloop:
    cmp byte [ecx+eax], 1                    ; carry flag will be set if 0
    inc eax                                  ; increment counter
    jnc short .lenloop                       ; keep looping if carry flag is not set
    dec eax                                  ; do not count null byte at the end
    retn 4

; ===============================================
; strcat - return concatenated string
; -----------------------------------
; strcat(string, buffer, buffer_size)
; return concatenated strings into string 1
; ===============================================
strcat:
    push esi
    push edi
    mov edi, [esp+16]                        ; destination (buffer)
    push edi                                 ; get size of string
    call strlen                              ;
    mov edx, eax                             ; set size as offset
    mov esi, [esp+12]                        ; string to add
    push esi                                 ; get size of string to add
    call strlen                              ;
    mov ecx, eax                             ; set size as counter
    add edi, edx                             ; set offset to concatenate string
    add eax, edx                             ; eax = string 1 size + string 2 size
    cmp eax, [esp+20]                        ; eax < buffer size ?
    jge short .return                        ; avoid overflow
    rep movsb                                ; copy bytes
    mov byte [edi], 0                        ; null byte at the end of the concatenated strings
.return:
    pop edi
    pop esi
    retn 12                                  ; length is returned in eax

; ===============================================
; strtoll - convert string to qword
; ---------------------------------
; strtoll(string)
; return value in eax - low order dword
; return value in edx - high order dword
; ===============================================
strtoll:
    push ebp
    mov ebp, esp
    sub esp, 8                               ; allocate 1 qword for the return value
    push ebx
    push esi
    mov esi, [ebp+8]                         ; string in esi
    xor eax, eax                             ; reset eax so we can store our value there
    xor edx, edx                             ; reset edx
    mov dword [ebp-4], eax
    mov dword [ebp-8], eax
    mov ebx, 0x0A                            ; we are going to multiply and divide by 10
.lenloop:
    cmp byte [esi], 0x30                     ; if below 0x30 (0) return
    jb short .finish
    cmp byte [esi], 0x39                     ; if above 0x30 (9) return
    ja short .finish
    lodsb                                    ; load byte from string into al
    sub al, 0x30                             ; value - 0x30 = converted number
    ; add with carry
    add dword [ebp-4], eax                   ; add value to low order
    adc dword [ebp-8], 0                     ; add carried part to high order
    jc short .return                         ; overflow ?
    ; multiply 1st dword
    mov eax, [ebp-4]                         ; multiply by 10
    mul ebx                                  ; 
    mov dword [ebp-4], eax                   ; save result
    mov ecx, edx                             ; save carried part in ECX
    ; multiply 2nd dword with carry
    mov eax, [ebp-8]
    mul ebx
    add eax, ecx                             ; add carried part from previous multiplication
    mov dword [ebp-8], eax
    ; check for overflow
    test edx, edx
    jne short .overflow                      ; overflow ?
    jmp short .lenloop
.overflow:
    xor edx, edx
    mov dword [ebp-8], edx
    mov dword [ebp-4], edx
    jmp short .return
.finish:
    xor edx, edx
    mov eax, [ebp-8]                         ; high order
    div ebx                                  ; divide by 10
    mov dword [ebp-8], eax                   ; replace with new value
    mov eax, [ebp-4]                         ; low order
    div ebx                                  ; divide by 10
    mov dword [ebp-4], eax                   ; replace with new value
.return:
    mov eax, [ebp-4]
    mov edx, [ebp-8]
    pop esi
    pop ebx
    mov esp, ebp
    pop ebp
    retn 4                                   ; converted value is returned in edx:eax
    
SECTION .bss
    hWnd                           resd 1
    hInstance                      resd 1
    WndClass                       resd 12   ; WNDCLASS
    Msg                            resd 12   ; MSG
    nid                            resb 488  ; NOTIFYICONDATA

    bufferOut                      resq 1
    bufferReply                    resb 1024
    headerValue                    resb 128
    xmlValue                       resb 256
    sock                           resd 1
    usagePercentage                resd 1
    dataplanUsage                  resd 1
    
    ;; WSADATA STRUC - 406 bytes
    WSADATA                        resb 406
    ;STRUC WSAData
    ;    .wVersion                  resw 1
    ;    .wHighVersion              resw 1
    ;    .szDescription             resb 257
    ;    .szSystemStatus            resb 129
    ;    .iMaxSockets               resw 1
    ;    .iMaxUdpDg                 resw 1
    ;    .lpVenderInfo              resd 1
    ;ENDSTRUC
    
    ;; sockaddr_in STRUCT - 24 bytes
    sockAddr                       resb 24
    ;STRUC sockaddr_in
    ;    .sin_family                resw 1
    ;    .sin_port                  resw 1
    ;    .sin_addr                  resd 1
    ;    .sin_zero                  resb 8
    ;ENDSTRUC

SECTION .data
    ClassName                      db   "DataplanMonitor", 0
    AppName                        db   "Data Plan Monitor", 0
    WM_SHELLNOTIFY                 equ  1001
    ID_TRAY_EXIT                   equ  1011
    IDT_UPDATE                     equ  1022
    TXT_TRAY_EXIT                  db   "Exit", 0
    TRAY_FONT                      db   "Arial", 0
    TRAY_FONT_W                    equ  5
    TRAY_FONT_H                    equ  12
    timerInterval                  equ  300000 ; 5mn interval in ms
    ;; info
    info                           db   "INFO", 0
    ;; error messages
    err                            db   "ERROR", 0
    errWindow                      db   "Error while creating new window. ", 0
    errWinsock                     db   "Error while initializing Winsock", 0
    errSocket                      db   "Error while creating socket", 0
    errServer                      db   "Error while connecting to server.", 10, "Check port and ip settings.", 0
    errGetRequest                  db   "Error while sending GET request", 0
    errReply                       db   "Error while receiving reply from server", 0
    errReplyOverflow               db   "Error while receiving reply from server (overflow)", 0
    errDataplan                    db   "Error while getting dataplan percentage", 0
    ;; tooltip
    toolTipD                       db   "Down: ", 0
    toolTipU                       db   "Up: ", 0
    toolTipPlan                    db   "Plan: ", 0
    toolTipB                       db   " bytes", 10, 0
    toolTipMB                      db   " MB", 10, 0
    ;; http field
    httpContentLength              db   "Content-Length", 0
    ;; http header
    httpVerHost                    db   " HTTP/1.1", 13, 10, "Host: ", 0
    httpUAAccept                   db   13, 10, "User-Agent: Dataplan Monitor", 13, 10, "Accept: */*", 13, 10, 13, 10, 0
    ;; server settings
    ip                             db   "192.168.1.1", 0
    port                           equ  80
    ;; get requests
    getMethod                      db   "GET ", 0
    getMonthStats                  db   "/api/monitoring/month_statistics", 0
    getStartDate                   db   "/api/monitoring/start_date", 0
    ;; XML tags
    xmlCurrentDownload             db   "CurrentMonthDownload", 0
    xmlCurrentUpload               db   "CurrentMonthUpload", 0
    xmlDataLimit                   db   "DataLimit", 0
