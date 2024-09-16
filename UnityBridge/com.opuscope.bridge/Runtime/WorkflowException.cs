using System;

namespace Opuscope.Bridge
{
    public class RuntimeWorkflowException : Exception
    {
        public string Type { get; }
        
        public RuntimeWorkflowException(string type, string message)
            : base(message)
        {
            Type = type;
        }

        public RuntimeWorkflowException(string message)
            : base(message)
        {
        }

        public RuntimeWorkflowException(string message, Exception inner)
            : base(message, inner)
        {
        }
    }
    
    public class InvalidWorkflowException : Exception
    {
        public InvalidWorkflowException()
        {
        }

        public InvalidWorkflowException(string message)
            : base(message)
        {
        }

        public InvalidWorkflowException(string message, Exception inner)
            : base(message, inner)
        {
        }
    }
}