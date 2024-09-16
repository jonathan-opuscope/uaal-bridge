using System;
using System.Collections.Generic;
using Newtonsoft.Json;
using UniRx;
using UnityEngine;

namespace Opuscope.Bridge
{
    public class BridgeMessage
    {
        [JsonProperty("path")]
        public string Path { get; set; }

        [JsonProperty("content")]
        public string Content { get; set; }

        public override string ToString()
        {
            return $"{GetType().Name} {nameof(Path)} {Path} {nameof(Content)} {Content}";
        }
    }
    
    public interface IBridgeListener
    {
        IObservable<BridgeMessage> Messages { get; }
    }

    public interface IBridgeMessenger
    {
        void SendMessage(string path, string content);
    }
    
    public interface IBridge
    {
        IObservable<BridgeMessage> Publish(string path);

        void Send<T>(string path, T content);
        
        JsonSerializerSettings JsonSerializerSettings { get; }
    }
    
    public static class BridgeExtensions
    {
        public static IObservable<T> PublishContent<T>(this IBridge bridge, string path, JsonSerializerSettings jsonSerializerSettings = null) where T : class
        {
            return bridge.Publish(path).Decode<T>(jsonSerializerSettings);
        }
    }
    
    public class Bridge : IBridge, IDisposable
    {
        private readonly IBridgeMessenger _messenger;
        private IDisposable _notificationSubscription;
        private readonly Dictionary<string, Subject<BridgeMessage>> _subjects = new ();
        
        public JsonSerializerSettings JsonSerializerSettings { get; }

        public Bridge(IBridgeMessenger messenger, IBridgeListener listener, JsonSerializerSettings _serializerSettings = null)
        {
            JsonSerializerSettings = _serializerSettings ?? new JsonSerializerSettings();
            _messenger = messenger;
            _notificationSubscription = listener.Messages.Subscribe(notification =>
            {
                if (_subjects.TryGetValue(notification.Path, out Subject<BridgeMessage> subject))
                {
                    subject.OnNext(notification);
                }
            });
        }

        public void Dispose()
        {
            foreach (Subject<BridgeMessage> subject in _subjects.Values)
            {
                subject.Dispose();
            }
            _subjects.Clear();
            _notificationSubscription?.Dispose();
            _notificationSubscription = null;
        }

        public void Send<T>(string path, T content)
        {
            try
            {
                string serialized = JsonConvert.SerializeObject(content, JsonSerializerSettings);
                _messenger.SendMessage(path, serialized);
            }
            catch (Exception e)
            {
                Debug.LogError($"Failed to serialize message content {e}");
                throw;
            }
        }

        public IObservable<BridgeMessage> Publish(string path)
        {
            if (_subjects.TryGetValue(path, out Subject<BridgeMessage> subject))
            {
                return subject.AsObservable();
            }
            subject = new Subject<BridgeMessage>();
            _subjects[path] = subject;
            return subject.AsObservable();
        }
    }

}
