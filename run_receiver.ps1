# 引入 Win32 API (仅在主 Runspace 加载一次)
$code = @"
using System;
using System.Runtime.InteropServices;
using System.Threading;

public class KeyboardInput {
    [DllImport("user32.dll")]
    public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, uint dwExtraInfo);

    const int VK_CONTROL = 0x11;
    const int VK_V = 0x56;
    const uint KEYEVENTF_KEYUP = 0x0002;

    public static void Paste() {
        // Press Ctrl
        keybd_event((byte)VK_CONTROL, 0, 0, 0);
        // Press V
        keybd_event((byte)VK_V, 0, 0, 0);
        
        // Release V
        keybd_event((byte)VK_V, 0, KEYEVENTF_KEYUP, 0);
        // Release Ctrl
        keybd_event((byte)VK_CONTROL, 0, KEYEVENTF_KEYUP, 0);
    }
}
"@

# 尝试加载类型，如果已存在则跳过
try {
    Add-Type -TypeDefinition $code -Language CSharp
} catch {
    # 类型可能已加载，忽略错误
}

# 初始化 UDP
$port = 11000
$udpClient = New-Object System.Net.Sockets.UdpClient($port)
$remoteEndPoint = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Any, 0)

# 获取并显示本机 IP 地址
Write-Host "==========================================" -ForegroundColor Gray
Write-Host "Android2PC Receiver Started" -ForegroundColor White
Write-Host "Listening on UDP port: $port" -ForegroundColor Green
Write-Host "------------------------------------------" -ForegroundColor Gray
Write-Host "Available IP Addresses:" -ForegroundColor Cyan

try {
    # 获取所有网络接口
    $interfaces = [System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces()
    foreach ($iface in $interfaces) {
        # 只显示 Up 状态的接口，且不是回环接口
        if ($iface.OperationalStatus -eq 'Up' -and $iface.NetworkInterfaceType -ne 'Loopback') {
            $props = $iface.GetIPProperties()
            foreach ($addr in $props.UnicastAddresses) {
                # 只显示 IPv4
                if ($addr.Address.AddressFamily -eq 'InterNetwork') {
                    $ip = $addr.Address.ToString()
                    # 过滤掉 169.254.x.x (APIPA)
                    if (-not $ip.StartsWith("169.254")) {
                        Write-Host "  [$($iface.Name)] -> $ip" -ForegroundColor Yellow
                    }
                }
            }
        }
    }
} catch {
    Write-Warning "Failed to list IP addresses: $_"
}

Write-Host "------------------------------------------" -ForegroundColor Gray
Write-Host "Please enter one of the above IPs on your phone." -ForegroundColor White
Write-Host "==========================================" -ForegroundColor Gray

try {
    while ($true) {
        if ($udpClient.Available -gt 0) {
            # 接收数据
            $data = $udpClient.Receive([ref]$remoteEndPoint)
            $text = [System.Text.Encoding]::UTF8.GetString($data)
            
            Write-Host "Received from $($remoteEndPoint.Address): $text" -ForegroundColor Yellow

            # --- 日志记录 ---
            try {
                $logFile = Join-Path $PSScriptRoot "received_messages.txt"
                $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                $logEntry = "[$timestamp] From $($remoteEndPoint.Address): $text"
                Add-Content -Path $logFile -Value $logEntry -Encoding UTF8
            } catch {
                Write-Warning "Failed to write log: $_"
            }
            # ----------------

            # --- 发送 ACK 回执 ---
            try {
                $ackBytes = [System.Text.Encoding]::UTF8.GetBytes("ACK")
                [void]$udpClient.Send($ackBytes, $ackBytes.Length, $remoteEndPoint)
            } catch {
                Write-Warning "Failed to send ACK: $_"
            }
            # ---------------------

            # 显式创建 Runspace 并设置为 STA
            $runspace = [runspacefactory]::CreateRunspace()
            $runspace.ApartmentState = "STA"
            $runspace.ThreadOptions = "ReuseThread"
            $runspace.Open()

            try {
                $ps = [powershell]::Create()
                $ps.Runspace = $runspace
                
                # 使用 [void] 强制忽略 AddScript/AddArgument 的返回值
                [void]$ps.AddScript({
                    param($txt)
                    Add-Type -AssemblyName System.Windows.Forms
                    try {
                        [System.Windows.Forms.Clipboard]::SetText($txt)
                    } catch {
                        # 忽略剪贴板错误
                    }
                }).AddArgument($text)
                
                # 忽略 Invoke 的返回值
                [void]$ps.Invoke()
            } finally {
                $ps.Dispose()
                $runspace.Close()
                $runspace.Dispose()
            }

            # 模拟按键（在主线程执行即可，Win32 API 是线程安全的）
            Start-Sleep -Milliseconds 50
            [KeyboardInput]::Paste()
        }
        Start-Sleep -Milliseconds 50
    }
}
catch {
    Write-Error "Error: $_"
}
finally {
    $udpClient.Close()
    Write-Host "Service stopped." -ForegroundColor Red
}
