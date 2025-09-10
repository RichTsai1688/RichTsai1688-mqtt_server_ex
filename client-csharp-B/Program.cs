using System.Text;
using System.Text.Json;
using MQTTnet;
using MQTTnet.Client;
using MQTTnet.Formatter;

class Program
{
    // MQTT 配置 - 可通過環境變數覆蓋
    static string Host = Environment.GetEnvironmentVariable("MQTT_BROKER_IP") ?? "140.134.60.218";
    static int Port = int.Parse(Environment.GetEnvironmentVariable("MQTT_PORT") ?? "4883");  // TLS 改成 MQTT_TLS_PORT
    static int TlsPort = int.Parse(Environment.GetEnvironmentVariable("MQTT_TLS_PORT") ?? "4884");
    static string Id = Environment.GetEnvironmentVariable("MQTT_CLIENT_ID") ?? "id1";
    static string User = Environment.GetEnvironmentVariable("MQTT_B_USER") ?? "B_user";
    static string Pass = Environment.GetEnvironmentVariable("MQTT_B_PASSWORD") ?? "B_password";

    static string TOP_CTRL_START = $"v1/{Id}/ctrl/start";
    static string TOP_CTRL_END   = $"v1/{Id}/ctrl/end";
    static string TOP_CMD_POINT  = $"v1/{Id}/cmd/point";
    static string TOP_RESULT     = $"v1/{Id}/telemetry/result";
    static string TOP_SETTING    = $"v1/{Id}/config/setting";
    static string TOP_STATUS     = $"v1/{Id}/status";

    // 用於去重的快取（幂等性保證）
    static Dictionary<string, object> _processedRequests = new Dictionary<string, object>();
    static readonly object _cacheLock = new object();

    static async Task Main()
    {
        Console.WriteLine("=== B 客戶端（執行端）啟動中 ===");
        
        var factory = new MqttFactory();
        var client = factory.CreateMqttClient();

        client.ConnectedAsync += async e =>
        {
            Console.WriteLine("B 客戶端連接成功");
            
            // 訂閱主題
            await client.SubscribeAsync(TOP_CMD_POINT, MQTTnet.Protocol.MqttQualityOfServiceLevel.AtLeastOnce);
            await client.SubscribeAsync(TOP_CTRL_END, MQTTnet.Protocol.MqttQualityOfServiceLevel.AtLeastOnce);
            Console.WriteLine("已訂閱必要主題");

            // 發送上線狀態（retained）
            var status = JsonSerializer.Serialize(new 
            { 
                online = true, 
                sender = "B", 
                ts = DateTimeOffset.UtcNow.ToUnixTimeSeconds(), 
                state = "ready",
                version = "1.0.0"
            });
            await client.PublishStringAsync(TOP_STATUS, status, MQTTnet.Protocol.MqttQualityOfServiceLevel.AtLeastOnce, retain: true);
            Console.WriteLine("已發送上線狀態");

            // 推送初始設定（retained）
            var setting = JsonSerializer.Serialize(new 
            {
                type = "setting",
                parameters = new 
                { 
                    start_x = 0, 
                    start_y = 0, 
                    x_min = -50, 
                    x_max = 50, 
                    y_min = -50, 
                    y_max = 50, 
                    sig_x_min = 0.1, 
                    sig_y_min = 0.1,
                    analysis_mode = "full_spectrum",
                    sampling_rate = 1000
                },
                ts = DateTimeOffset.UtcNow.ToUnixTimeSeconds(),
                sender = "B",
                version = "2025.09.10-01"
            });
            await client.PublishStringAsync(TOP_SETTING, setting, MQTTnet.Protocol.MqttQualityOfServiceLevel.ExactlyOnce, retain: true);
            Console.WriteLine("已發送初始設定");

            // 等待一秒後由 B 觸發 start（模擬設備就緒）
            await Task.Delay(1000);
            
            var startMsg = JsonSerializer.Serialize(new 
            { 
                type = "start", 
                ts = DateTimeOffset.UtcNow.ToUnixTimeSeconds(), 
                sender = "B", 
                job_id = $"job-{Id}-{Guid.NewGuid().ToString()[..8]}",
                message = "設備就緒，可開始測量"
            });
            await client.PublishStringAsync(TOP_CTRL_START, startMsg, MQTTnet.Protocol.MqttQualityOfServiceLevel.AtLeastOnce, retain: false);
            Console.WriteLine("已發送 START 信號，等待 A 端指令...");
        };

        client.ApplicationMessageReceivedAsync += async e =>
        {
            try
            {
                var topic = e.ApplicationMessage.Topic;
                var json = Encoding.UTF8.GetString(e.ApplicationMessage.PayloadSegment);
                
                Console.WriteLine($"收到消息 - Topic: {topic}");
                
                using var doc = JsonDocument.Parse(json);
                var root = doc.RootElement;

                if (topic == TOP_CMD_POINT && root.GetProperty("type").GetString() == "move_point")
                {
                    await HandleMovePointCommand(client, root);
                }
                else if (topic == TOP_CTRL_END && root.GetProperty("type").GetString() == "end")
                {
                    Console.WriteLine($"[B] 收到 END 信號: {root}");
                    
                    // 更新狀態為完成
                    var status = JsonSerializer.Serialize(new 
                    { 
                        online = true, 
                        sender = "B", 
                        ts = DateTimeOffset.UtcNow.ToUnixTimeSeconds(), 
                        state = "completed"
                    });
                    await client.PublishStringAsync(TOP_STATUS, status, MQTTnet.Protocol.MqttQualityOfServiceLevel.AtLeastOnce, retain: true);
                    
                    // 清理快取
                    lock (_cacheLock)
                    {
                        _processedRequests.Clear();
                    }
                    Console.WriteLine("工作流程結束，快取已清理");
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine($"處理消息時發生錯誤: {ex.Message}");
            }
        };

        client.DisconnectedAsync += async e =>
        {
            Console.WriteLine($"B 客戶端斷線: {e.Reason}");
            if (e.ClientWasConnected)
            {
                Console.WriteLine("嘗試重新連接...");
                await Task.Delay(5000);
            }
        };

        var options = new MqttClientOptionsBuilder()
            .WithTcpServer(Host, Port)
            .WithClientId("B-" + Id)
            .WithCredentials(User, Pass)
            .WithProtocolVersion(MqttProtocolVersion.V311)
            .WithKeepAlivePeriod(TimeSpan.FromSeconds(45))
            // 設置遺囑
            .WithWillTopic(TOP_STATUS)
            .WithWillPayload(JsonSerializer.Serialize(new 
            { 
                online = false, 
                sender = "B", 
                ts = DateTimeOffset.UtcNow.ToUnixTimeSeconds(),
                state = "disconnected"
            }))
            .WithWillQualityOfServiceLevel(MQTTnet.Protocol.MqttQualityOfServiceLevel.AtLeastOnce)
            .WithWillRetain(true)
            .Build();

        try
        {
            Console.WriteLine($"正在連接到 {Host}:{Port}...");
            await client.ConnectAsync(options);
            
            Console.WriteLine("B 客戶端運行中，按任意鍵退出...");
            Console.ReadKey();
        }
        catch (Exception ex)
        {
            Console.WriteLine($"連接失敗: {ex.Message}");
        }
        finally
        {
            await client.DisconnectAsync();
        }
    }

    static async Task HandleMovePointCommand(IMqttClient client, JsonElement root)
    {
        var x = root.GetProperty("point").GetProperty("x").GetDouble();
        var y = root.GetProperty("point").GetProperty("y").GetDouble();
        var reqId = root.TryGetProperty("req_id", out var rid) ? rid.GetString() : null;
        var sender = root.TryGetProperty("sender", out var s) ? s.GetString() : "unknown";

        Console.WriteLine($"[B] 收到移動點位指令: ({x:F2}, {y:F2}), req_id: {reqId}");

        // 幂等性檢查
        lock (_cacheLock)
        {
            if (!string.IsNullOrEmpty(reqId) && _processedRequests.ContainsKey(reqId))
            {
                Console.WriteLine($"[B] 檢測到重複請求 {reqId}，返回快取結果");
                var cachedResult = _processedRequests[reqId];
                await client.PublishStringAsync(TOP_RESULT, JsonSerializer.Serialize(cachedResult), 
                    MQTTnet.Protocol.MqttQualityOfServiceLevel.AtLeastOnce, retain: false);
                return;
            }
        }

        try
        {
            // 模擬設備移動與測量過程
            Console.WriteLine($"[B] 開始移動到位置 ({x:F2}, {y:F2})...");
            await SimulateMovement(x, y);
            
            Console.WriteLine($"[B] 開始振動分析...");
            await SimulateVibrationAnalysis();
            
            // 生成模擬的振動特徵值
            var features = GenerateVibrationFeatures(x, y);
            
            var resultObj = new
            {
                type = "result_feature_set",
                features = new[] 
                {
                    "Time_skewness_y", "Time_kurtosis_y", "Time_rms_y", "Time_crestfactor_y",
                    "Powerspectrum_skewness_y", "Powerspectrum_kurtosis_y",
                    "Powerspectrum_rms_y", "Powerspectrum_crestfactor_y"
                },
                values = features,
                point = new { x, y },
                ts = DateTimeOffset.UtcNow.ToUnixTimeSeconds(),
                sender = "B",
                req_id = reqId,   // 關鍵：回帶 req_id
                analysis_info = new
                {
                    duration_ms = 200,
                    sampling_rate = 1000,
                    data_points = 200,
                    algorithm_version = "v2.1.0"
                }
            };

            // 快取結果（用於幂等性）
            if (!string.IsNullOrEmpty(reqId))
            {
                lock (_cacheLock)
                {
                    _processedRequests[reqId] = resultObj;
                    
                    // 限制快取大小（保留最近 100 個）
                    if (_processedRequests.Count > 100)
                    {
                        var oldestKey = _processedRequests.Keys.First();
                        _processedRequests.Remove(oldestKey);
                    }
                }
            }

            // 發送結果
            var resultJson = JsonSerializer.Serialize(resultObj);
            await client.PublishStringAsync(TOP_RESULT, resultJson, 
                MQTTnet.Protocol.MqttQualityOfServiceLevel.AtLeastOnce, retain: false);
            
            Console.WriteLine($"[B] 已發送分析結果 req_id: {reqId}");
        }
        catch (Exception ex)
        {
            Console.WriteLine($"[B] 處理點位 ({x:F2}, {y:F2}) 時發生錯誤: {ex.Message}");
            
            // 發送錯誤結果
            var errorResult = new
            {
                type = "result_error",
                error = ex.Message,
                point = new { x, y },
                ts = DateTimeOffset.UtcNow.ToUnixTimeSeconds(),
                sender = "B",
                req_id = reqId
            };
            
            await client.PublishStringAsync(TOP_RESULT, JsonSerializer.Serialize(errorResult),
                MQTTnet.Protocol.MqttQualityOfServiceLevel.AtLeastOnce, retain: false);
        }
    }

    static async Task SimulateMovement(double x, double y)
    {
        // 模擬移動時間（根據距離）
        var distance = Math.Sqrt(x * x + y * y);
        var moveTime = Math.Max(100, (int)(distance * 10)); // 最少 100ms
        await Task.Delay(moveTime);
    }

    static async Task SimulateVibrationAnalysis()
    {
        // 模擬振動分析時間
        await Task.Delay(200);
    }

    static double[] GenerateVibrationFeatures(double x, double y)
    {
        // 基於位置生成模擬的振動特徵（讓數據有一定規律性）
        var random = new Random((int)(x * 1000 + y * 1000));
        
        // 模擬不同位置有不同的振動特性
        var baseAmplitude = 1.0 + Math.Abs(x) * 0.1 + Math.Abs(y) * 0.05;
        var noise = (random.NextDouble() - 0.5) * 0.2;
        
        return new double[]
        {
            // Time domain features
            (random.NextDouble() - 0.5) * 2 + noise,           // skewness_y
            random.NextDouble() * 3 + 2 + noise,               // kurtosis_y  
            baseAmplitude * (0.5 + random.NextDouble() * 0.5), // rms_y
            2.0 + random.NextDouble() * 2 + noise,             // crestfactor_y
            
            // Power spectrum features  
            (random.NextDouble() - 0.5) * 1.5 + noise,         // PS skewness_y
            random.NextDouble() * 2 + 1.5 + noise,             // PS kurtosis_y
            baseAmplitude * (0.3 + random.NextDouble() * 0.4), // PS rms_y
            1.5 + random.NextDouble() * 1.5 + noise            // PS crestfactor_y
        };
    }
}
