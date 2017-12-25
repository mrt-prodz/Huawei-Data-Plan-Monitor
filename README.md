# Huawei Data Plan Monitor
 
#### System tray icon showing your current data plan usage with NASM/GoLink

Display a system tray icon and report available traffic from your dataplan by making API queries to your Huawei modem. Setup your data plan inside your Huawei web administration panel:

http://[your modem ip]/html/statistic.html

The program will fetch the month current download and upload statistics along with the monthly data plan and display the usage percentage on the icon.

The value will be refreshed every 5 minutes.

The purpose of this project was that I needed a way to check easily my data plan usage without login into my modem administration panel each time. It's an annoying surprise to discover you reached the end of your data plan and have no more internet access.

After quickly looking into the communication between my browser and the modem itself I noticed I could make direct API calls and get the information I needed without being logged in. It was also a nice little project to practice assembly and using the Win32 API.

This program works with a Huawei E5220 device using Software Version 21.143.11.00.784 and Web UI Version 13.100.02.00.784. If you are using another model, software and/or web ui version it would be great if you could report it.

## Features:
* Show current data plan usage (percentage)
* Tooltip showing monthly current upload and download usage
* Refresh percentage value every 5 minutes
* Reconnect attempt after failing to retrieve value
* Relatively small (around 6KB)

This is a Windows project, Makefile and code have been created for NASM/GoLink.

## Screenshot:
![Data Plan Monitor](https://raw.githubusercontent.com/mrt-prodz/Huawei-Data-Plan-Monitor/master/screenshot1.png)

![Data Plan Monitor](https://raw.githubusercontent.com/mrt-prodz/Huawei-Data-Plan-Monitor/master/screenshot2.png)

![Data Plan Monitor](https://raw.githubusercontent.com/mrt-prodz/Huawei-Data-Plan-Monitor/master/screenshot3.png)

## Could be nice:
* Making another version as a Windows Service
* Adding configuration file support to easily change the IP and Port of the modem

## Reference:
[Winsock Reference](https://msdn.microsoft.com/en-us/library/windows/desktop/ms741416(v=vs.85).aspx)

[Shell_NotifyIcon function](https://msdn.microsoft.com/en-us/library/windows/desktop/bb762159(v=vs.85).aspx)

[Working With Big Numbers Using x86 Instructions](http://x86asm.net/articles/working-with-big-numbers-using-x86-instructions)

[x86 Instruction Listings](http://en.wikipedia.org/wiki/X86_instruction_listings)

[x86 Disassembly](http://en.wikibooks.org/wiki/X86_Disassembly)

[Intel Pentium Instruction Set Reference (Basic Architecture Overview)](http://faydoc.tripod.com/cpu/)

[NASM](http://www.nasm.us/)

[GoLink](http://www.godevtool.com/)
