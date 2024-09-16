using System;
using Newtonsoft.Json;

namespace Opuscope.Bridge
{
    public class WorkflowCompletion
    {
        public static string Path => "/workflow/completed";
    
        [JsonProperty("identifier")]
        public string Identifier { get; set; }
    
        [JsonProperty("result")]
        public string Result { get; set; }
        
        public override string ToString()
        {
            return $"{GetType().Name} {nameof(Identifier)} {Identifier} {nameof(Result)} {Result}";
        }

        public static WorkflowCompletion Make(string identifier, string result) => new ()
        {
            Identifier = identifier,
            Result = result
        };
    }

    public class WorkflowFailure
    {
        public static string Path => "/workflow/failed";

        public struct ErrorTypes
        {
            public const string CancelledWorkflow = "CancelledWorkflow";
            public const string InvalidWorkflow = "InvalidWorkflow";            
        }
        
        [JsonProperty("identifier")]
        public string Identifier { get; set; }
    
        [JsonProperty("type")]
        public string Type { get; set; }
    
        [JsonProperty("message")]
        public string Message { get; set; }
        
        public override string ToString()
        {
            return $"{GetType().Name} {nameof(Identifier)} {Identifier} {nameof(Type)} {Type} {nameof(Message)} {Message}";
        }
        
        public static WorkflowFailure Make(string identifier, Exception e)
        {
            return e switch
            {
                OperationCanceledException operationCanceledException 
                    => new WorkflowFailure {Identifier = identifier, Type = ErrorTypes.CancelledWorkflow},
                InvalidWorkflowException invalidWorkflowException 
                    => new WorkflowFailure {Identifier = identifier, Type = ErrorTypes.InvalidWorkflow, Message = invalidWorkflowException.Message},
                RuntimeWorkflowException runtimeWorkflowException 
                    => new WorkflowFailure {Identifier = identifier, Type = runtimeWorkflowException.Type, Message = runtimeWorkflowException.Message},
                _ => new WorkflowFailure {Identifier = identifier, Type = e.GetType().Name, Message = e.Message}
            };
        }

        public Exception ToException()
        {
            return Type switch
            {
                ErrorTypes.CancelledWorkflow => new OperationCanceledException(),
                ErrorTypes.InvalidWorkflow => new InvalidWorkflowException(Message),
                _ => new RuntimeWorkflowException(Type, Message)
            };
        }
    }

    public class WorkflowRequest
    {
        public static string Path => "/workflow/request";
    
        [JsonProperty("identifier")]
        public string Identifier { get; set; }
    
        [JsonProperty("procedure")]
        public string Procedure { get; set; }
    
        [JsonProperty("payload")]
        public string Payload { get; set; }

        public override string ToString()
        {
            return $"{GetType().Name} {nameof(Identifier)} {Identifier} {nameof(Procedure)} {Procedure} {nameof(Payload)} {Payload}";
        }
    }

    public class WorkflowCancellation
    {
        public static string Path => "/workflow/cancel";
    
        [JsonProperty("identifier")]
        public string Identifier { get; set; }
        
        public override string ToString()
        {
            return $"{GetType().Name} {nameof(Identifier)} {Identifier}";
        }
    }
}