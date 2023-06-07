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
    }

    [JsonObject(NamingStrategyType = typeof(CamelCaseNamingStrategy))]
    class TestResult
    {
        public string Message;
        public int Processed;
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
        await TestImmediateWorkflow();
    }

    private async UniTask TestImmediateWorkflow()
    {
        // note : duration is not taken into account
        TestPayload payload = new TestPayload {Name = "Gertrude", Number = 42, Duration = 1000};
        TestResult result = await _workflowPerformer.Perform<TestPayload, TestResult>(Procedures.ImmediateGreeting, payload, CancellationToken.None);
    }
    
    private async UniTask TestDelayedWorkflow()
    {
        TestPayload payload = new TestPayload {Name = "Norbert", Number = 666, Duration = 5};
        TestResult result = await _workflowPerformer.Perform<TestPayload, TestResult>(Procedures.DelayedGreeting, payload, CancellationToken.None);
    }
    
    private async UniTask TestConcurrentWorkflow()
    {
        TestPayload payload1 = new TestPayload {Name = "Brigitte", Number = 42, Duration = 2};
        TestPayload payload2 = new TestPayload {Name = "Norbert", Number = 666, Duration = 5};
        TestPayload payload3 = new TestPayload {Name = "Gertrude", Number = 404, Duration = 4};
        
        UniTask<TestResult> task1 = _workflowPerformer.Perform<TestPayload, TestResult>(Procedures.DelayedGreeting, payload1, CancellationToken.None);
        UniTask<TestResult> task2 = _workflowPerformer.Perform<TestPayload, TestResult>(Procedures.DelayedGreeting, payload2, CancellationToken.None);
        UniTask<TestResult> task3 = _workflowPerformer.Perform<TestPayload, TestResult>(Procedures.DelayedGreeting, payload3, CancellationToken.None);

        TestResult result1 = await task1;
        TestResult result2 = await task2;
        TestResult result3 = await task3;
    }

    private async UniTask TestCancelledWorkflow()
    {
        
        TestPayload payload = new TestPayload {Name = "Norbert", Number = 666, Duration = 5};
        CancellationTokenSource source = new CancellationTokenSource();
        source.CancelAfter(TimeSpan.FromSeconds(2));
        try
        {
            TestResult result = await _workflowPerformer.Perform<TestPayload, TestResult>(Procedures.DelayedGreeting, payload, source.Token);
        }
        catch (OperationCanceledException e)
        {
            // expected
        }
    }
}
