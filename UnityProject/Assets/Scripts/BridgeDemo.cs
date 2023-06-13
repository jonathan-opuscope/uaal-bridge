using System;
using System.Runtime.InteropServices;
using System.Threading;
using Cysharp.Threading.Tasks;
using Newtonsoft.Json;
using Newtonsoft.Json.Serialization;
using Opuscope.Bridge;
using UniRx;
using UnityEngine;

class NativeBridge
{
    private const string INTERNAL = "__Internal";
#if UNITY_IOS
    [DllImport(INTERNAL)]
    public static extern void sendMessage(string path, string content);
#endif
}

class NativeBridgeMessenger : IBridgeMessenger
{
    public void SendMessage(string path, string content)
    {
        Debug.Log($"{this} {nameof(SendMessage)} to {path} : {content}");
#if UNITY_IOS
        NativeBridge.sendMessage(path, content);
#else
        throw new NotImplementedException();  
#endif
    }
}

public class BridgeDemo : MonoBehaviour
{
    private BroadcastingBridgeListener _bridgeListener;
    private Bridge _bridge;
    private BridgeWorkflowPerformer _workflowPerformer;
    private BridgeWorkflowRegister _workflowRegister;

    private readonly CompositeDisposable _subscriptions = new();
    
    [JsonObject(NamingStrategyType = typeof(CamelCaseNamingStrategy))]
    class TestPayload
    {
        public string Name;
        public int Number;
        public double Duration;

        public override string ToString()
        {
            return $"{GetType().Name} {nameof(Name)} {Name} {nameof(Number)} {Number} {nameof(Duration)} {Duration}";
        }
    }

    [JsonObject(NamingStrategyType = typeof(CamelCaseNamingStrategy))]
    class TestResult
    {
        public string Message;
        public int Processed;
        
        public override string ToString()
        {
            return $"{GetType().Name} {nameof(Message)} {Message} {nameof(Processed)} {Processed}";
        }
    }


    private struct Paths
    {
        public const string StartTest = "/test/start";
    }
    
    private struct Procedures
    {
        public const string ImmediateGreeting = "/greeting/immediate";
        public const string DelayedGreeting = "/greeting/delayed";
        public const string ErrorGreeting = "/greeting/error";
    }

    protected void Awake()
    {
        // avoid excessive logging ios side
        Application.SetStackTraceLogType(LogType.Log, StackTraceLogType.None);
        Application.SetStackTraceLogType(LogType.Warning, StackTraceLogType.None);
        Application.SetStackTraceLogType(LogType.Error, StackTraceLogType.None);
        
        _bridgeListener = new BroadcastingBridgeListener();
        _bridge = new Bridge(new NativeBridgeMessenger(), _bridgeListener);
        _workflowPerformer = new BridgeWorkflowPerformer(_bridge);
        _workflowRegister = new BridgeWorkflowRegister(_bridge);
        
        _workflowRegister.Register<TestPayload, TestResult>(Procedures.ImmediateGreeting, payload =>
        {
            return new TestResult
            {
                Message = $"Hello {payload.Name}", 
                Processed = payload.Number + 2
            };
        });
        
        _workflowRegister.Register<TestPayload, TestResult>(Procedures.DelayedGreeting, async (payload, token) =>
        {
            await UniTask.Delay(TimeSpan.FromSeconds(payload.Duration), cancellationToken: token);
            return new TestResult
            {
                Message = $"Hello {payload.Name}", 
                Processed = payload.Number + 2
            };
        });
        
        _workflowRegister.Register<TestPayload, TestResult>(Procedures.ErrorGreeting, async (payload, token) =>
        {
            await UniTask.Delay(TimeSpan.FromSeconds(payload.Duration), cancellationToken: token);
            throw new Exception("Error Greeting");
        });
    }

    protected void OnEnable()
    {
        _subscriptions.Add(_bridge.Publish(Paths.StartTest).Subscribe(_ =>
        {
            RunAll().Forget();
        }));
        _subscriptions.Add(_bridgeListener.Messages.Subscribe(message =>
        {
            Debug.Log($"{this} received {message}");
        }));
    }

    protected void OnDisable()
    {
        _subscriptions.Clear();
    }

    public void OnBridgeMessage(string message)
    {
        BridgeMessage bridgeMessage = JsonConvert.DeserializeObject<BridgeMessage>(message);
        if (bridgeMessage != null)
        {
            _bridgeListener.Broadcast(bridgeMessage);
        }
    }

    private async UniTask RunAll()
    {
        try
        {
            await TestImmediateWorkflow();
            await TestDelayedWorkflow();
            await TestCancelledWorkflow();

        }
        catch (Exception e)
        {
            Debug.LogError($"{nameof(RunAll)} unexpected exception {e}");
        }
    }

    private async UniTask TestImmediateWorkflow()
    {
        // note : duration is not taken into account
        TestPayload payload = new TestPayload {Name = "Gertrude", Number = 42, Duration = 1000};
        Debug.Log($"{GetType().Name} {nameof(TestImmediateWorkflow)} payload {payload}");
        TestResult result = await _workflowPerformer.Perform<TestPayload, TestResult>(Procedures.ImmediateGreeting, payload, CancellationToken.None);
        Debug.Log($"{GetType().Name} {nameof(TestImmediateWorkflow)} result {result}");
    }
    
    private async UniTask TestDelayedWorkflow()
    {
        TestPayload payload = new TestPayload {Name = "Norbert", Number = 666, Duration = 5};
        Debug.Log($"{GetType().Name} {nameof(TestDelayedWorkflow)} payload {payload}");
        TestResult result = await _workflowPerformer.Perform<TestPayload, TestResult>(Procedures.DelayedGreeting, payload, CancellationToken.None);
        Debug.Log($"{GetType().Name} {nameof(TestDelayedWorkflow)} result {result}");
    }
    
    private async UniTask TestConcurrentWorkflow()
    {
        TestPayload payload1 = new TestPayload {Name = "Brigitte", Number = 42, Duration = 2};
        TestPayload payload2 = new TestPayload {Name = "Norbert", Number = 666, Duration = 5};
        TestPayload payload3 = new TestPayload {Name = "Gertrude", Number = 404, Duration = 4};
        
        Debug.Log($"{GetType().Name} {nameof(TestConcurrentWorkflow)} payloads {payload1} {payload2} {payload3}");
        
        UniTask<TestResult> task1 = _workflowPerformer.Perform<TestPayload, TestResult>(Procedures.DelayedGreeting, payload1, CancellationToken.None);
        UniTask<TestResult> task2 = _workflowPerformer.Perform<TestPayload, TestResult>(Procedures.DelayedGreeting, payload2, CancellationToken.None);
        UniTask<TestResult> task3 = _workflowPerformer.Perform<TestPayload, TestResult>(Procedures.DelayedGreeting, payload3, CancellationToken.None);

        TestResult result1 = await task1;
        TestResult result2 = await task2;
        TestResult result3 = await task3;
        
        Debug.Log($"{GetType().Name} {nameof(TestConcurrentWorkflow)} results {result1} {result2} {result3}");
    }

    private async UniTask TestCancelledWorkflow()
    {
        TestPayload payload = new TestPayload {Name = "Norbert", Number = 666, Duration = 5};
        Debug.Log($"{GetType().Name} {nameof(TestCancelledWorkflow)} payload {payload}");
        CancellationTokenSource source = new CancellationTokenSource();
        source.CancelAfter(TimeSpan.FromSeconds(2));
        try
        {
            TestResult result = await _workflowPerformer.Perform<TestPayload, TestResult>(Procedures.DelayedGreeting, payload, source.Token);
        }
        catch (OperationCanceledException e)
        {
            Debug.Log($"{GetType().Name} {nameof(TestCancelledWorkflow)} expected cancellation occured");
        }
    }

    private async UniTask TestErrorWorkflow()
    {
        TestPayload payload = new TestPayload {Name = "Norbert", Number = 666, Duration = 5};
        Debug.Log($"{GetType().Name} {nameof(TestErrorWorkflow)} payload {payload}");
        try
        {
            TestResult result = await _workflowPerformer.Perform<TestPayload, TestResult>(Procedures.ErrorGreeting, payload, CancellationToken.None);
        }
        catch (RuntimeWorkflowException e)
        {
            Debug.Log($"{GetType().Name} {nameof(TestCancelledWorkflow)} expected error");
        }
    }
}
