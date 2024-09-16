using System;
using UniRx;

namespace Opuscope.Bridge
{
    public class BroadcastingBridgeListener : IBridgeListener
    {
        private readonly Subject<BridgeMessage> _messages = new();

        public IObservable<BridgeMessage> Messages => _messages.AsObservable();

        public void Broadcast(BridgeMessage message) => _messages.OnNext(message);
    }
}