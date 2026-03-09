using System.Net;
using System.Net.Sockets;
using System.Text;

namespace Android2PC_Server;

static class Program
{
    private static NotifyIcon? _notifyIcon;
    private static UdpClient? _udpServer;
    private static bool _isRunning = true;
    private const int PORT = 11000;

    /// <summary>
    ///  The main entry point for the application.
    /// </summary>
    [STAThread]
    static void Main()
    {
        ApplicationConfiguration.Initialize();

        // 设置托盘图标
        _notifyIcon = new NotifyIcon();
        _notifyIcon.Icon = SystemIcons.Application; // 这里使用默认图标，你可以换成自己的 .ico
        _notifyIcon.Text = $"Android2PC 接收服务 (端口: {PORT})";
        _notifyIcon.Visible = true;

        // 托盘右键菜单
        ContextMenuStrip contextMenu = new ContextMenuStrip();
        contextMenu.Items.Add("退出", null, (s, e) => Exit());
        _notifyIcon.ContextMenuStrip = contextMenu;

        // 启动 UDP 监听线程
        Thread serverThread = new Thread(StartUdpServer);
        serverThread.IsBackground = true;
        serverThread.Start();

        Application.Run();
    }

    private static void StartUdpServer()
    {
        try
        {
            _udpServer = new UdpClient(PORT);
            IPEndPoint remoteEP = new IPEndPoint(IPAddress.Any, 0);

            while (_isRunning)
            {
                // 接收数据
                byte[] data = _udpServer.Receive(ref remoteEP);
                string text = Encoding.UTF8.GetString(data);

                if (!string.IsNullOrEmpty(text))
                {
                    // 在 UI 线程执行粘贴操作
                    _notifyIcon?.Invoke((MethodInvoker)delegate {
                        PerformPaste(text);
                    });
                }
            }
        }
        catch (Exception ex)
        {
            MessageBox.Show($"UDP 服务出错: {ex.Message}", "错误", MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }

    private static void PerformPaste(string text)
    {
        try
        {
            // 1. 将文字写入剪贴板
            Clipboard.SetText(text);

            // 2. 模拟 Ctrl + V
            SendKeys.SendWait("^v");
        }
        catch (Exception ex)
        {
            // 忽略剪贴板占用错误
            System.Diagnostics.Debug.WriteLine($"粘贴失败: {ex.Message}");
        }
    }

    private static void Exit()
    {
        _isRunning = false;
        _notifyIcon!.Visible = false;
        _udpServer?.Close();
        Application.Exit();
    }
}
