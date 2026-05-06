using System;
using System.IO;
using System.Net;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;

namespace VPet_Simulator.Windows;

internal sealed class ResearchLifeIpcServer : IDisposable
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNameCaseInsensitive = true,
    };

    private readonly MainWindow window;
    private readonly object gate = new();
    private HttpListener listener;
    private CancellationTokenSource cancellation;
    private Task listenTask;
    private int port;

    public ResearchLifeIpcServer(MainWindow window)
    {
        this.window = window;
    }

    public bool IsRunning => listener?.IsListening == true;

    public void Start(int listenPort)
    {
        lock (gate)
        {
            if (IsRunning)
                return;

            port = listenPort;
            cancellation = new CancellationTokenSource();
            listener = new HttpListener();
            listener.Prefixes.Add($"http://127.0.0.1:{listenPort}/");
            listener.Start();
            listenTask = Task.Run(() => ListenAsync(cancellation.Token));
        }
    }

    public void Stop()
    {
        HttpListener currentListener;
        CancellationTokenSource currentCancellation;
        Task currentTask;

        lock (gate)
        {
            currentListener = listener;
            currentCancellation = cancellation;
            currentTask = listenTask;

            listener = null;
            cancellation = null;
            listenTask = null;
        }

        try
        {
            currentCancellation?.Cancel();
            currentListener?.Close();
        }
        catch
        {
        }

        try
        {
            currentTask?.Wait(500);
        }
        catch
        {
        }

        currentCancellation?.Dispose();
    }

    public void Dispose()
    {
        Stop();
    }

    private async Task ListenAsync(CancellationToken token)
    {
        while (!token.IsCancellationRequested)
        {
            HttpListenerContext context;
            try
            {
                context = await listener.GetContextAsync();
            }
            catch (ObjectDisposedException)
            {
                break;
            }
            catch (HttpListenerException)
            {
                break;
            }
            catch
            {
                if (token.IsCancellationRequested)
                    break;
                continue;
            }

            _ = Task.Run(() => HandleAsync(context), token);
        }
    }

    private async Task HandleAsync(HttpListenerContext context)
    {
        try
        {
            var request = context.Request;
            var path = request.Url?.AbsolutePath.Trim('/').ToLowerInvariant() ?? string.Empty;

            if (request.HttpMethod == "GET" && path == "status")
            {
                await WriteJsonAsync(context.Response, new
                {
                    ok = true,
                    running = true,
                    ready = window.Main != null,
                    version = window.Version,
                    prefix = window.PrefixSave,
                    port,
                });
                return;
            }

            if (request.HttpMethod == "POST" && path == "say")
            {
                await HandleSayAsync(context);
                return;
            }

            if (request.HttpMethod == "POST" && path == "close")
            {
                await WriteJsonAsync(context.Response, new
                {
                    ok = true,
                });
                _ = window.Dispatcher.BeginInvoke(new Action(() => window.Close()));
                return;
            }

            await WriteJsonAsync(context.Response, new
            {
                ok = false,
                error = "not_found",
            }, HttpStatusCode.NotFound);
        }
        catch (Exception ex)
        {
            try
            {
                await WriteJsonAsync(context.Response, new
                {
                    ok = false,
                    error = ex.Message,
                }, HttpStatusCode.InternalServerError);
            }
            catch
            {
            }
        }
    }

    private async Task HandleSayAsync(HttpListenerContext context)
    {
        var body = await ReadBodyAsync(context.Request);
        var request = string.IsNullOrWhiteSpace(body)
            ? null
            : JsonSerializer.Deserialize<SayRequest>(body, JsonOptions);
        var text = request?.Text?.Trim();

        if (string.IsNullOrWhiteSpace(text))
        {
            await WriteJsonAsync(context.Response, new
            {
                ok = false,
                error = "text_required",
            }, HttpStatusCode.BadRequest);
            return;
        }

        if (window.Main == null)
        {
            await WriteJsonAsync(context.Response, new
            {
                ok = false,
                error = "main_not_ready",
            }, HttpStatusCode.Conflict);
            return;
        }

        await window.Dispatcher.InvokeAsync(() =>
        {
            window.Main.Say(text, request.Graph, request.Force, request.Desc);
        });

        await WriteJsonAsync(context.Response, new
        {
            ok = true,
        });
    }

    private static async Task<string> ReadBodyAsync(HttpListenerRequest request)
    {
        using var reader = new StreamReader(request.InputStream, request.ContentEncoding ?? Encoding.UTF8);
        return await reader.ReadToEndAsync();
    }

    private static async Task WriteJsonAsync(HttpListenerResponse response, object payload, HttpStatusCode statusCode = HttpStatusCode.OK)
    {
        var json = JsonSerializer.Serialize(payload, JsonOptions);
        var buffer = Encoding.UTF8.GetBytes(json);

        response.StatusCode = (int)statusCode;
        response.ContentType = "application/json; charset=utf-8";
        response.ContentEncoding = Encoding.UTF8;
        response.ContentLength64 = buffer.Length;
        await response.OutputStream.WriteAsync(buffer, 0, buffer.Length);
        response.Close();
    }

    private sealed class SayRequest
    {
        public string Text { get; set; }
        public string Graph { get; set; }
        public string Desc { get; set; }
        public bool Force { get; set; } = true;
    }
}
