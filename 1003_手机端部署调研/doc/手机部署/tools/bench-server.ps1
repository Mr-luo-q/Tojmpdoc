# ============================================================
# 本文件已作废，请勿使用。
#
# 原因：它是用 UTF-8 无 BOM 保存的，Windows PowerShell 5.1 读取时会
#       按系统 ANSI（中文系统为 GBK）解码，中文注释被解成乱码，
#       行尾注释会吞掉后面的参数，报出莫名其妙的语法错误：
#         line 18: 函数参数列表中缺少 ")"
#         line 110: 哈希文本中的键后面缺少 "=" 运算符
#
# 可用版本在项目根目录：..\bench-server.ps1（已带 UTF-8 BOM，语法验证通过）
#
# 本文件目前删不掉：工作区根目录有一条 Everyone 的
# DeleteSubdirectoriesAndFiles 拒绝项，挡住了子项的删除操作。
# 请在资源管理器里手动删除，或用管理员权限的 del 命令。
# ============================================================

Write-Host "这个脚本是作废版本，请改用项目根目录的 bench-server.ps1" -ForegroundColor Red
Write-Host "路径：$([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\bench-server.ps1')))" -ForegroundColor Yellow
exit 1
