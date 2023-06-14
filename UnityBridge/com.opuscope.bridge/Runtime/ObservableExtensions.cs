using System;
using UnityEngine;
using Newtonsoft.Json;
using UniRx;

namespace Opuscope.Bridge
{
    public static class ObservableExtensions
    {
        private static readonly JsonSerializerSettings defaultSettings = new JsonSerializerSettings();
        
        public static IObservable<T> Decode<T>(this IObservable<BridgeMessage> input, 
            string path, 
            JsonSerializerSettings jsonSerializerSettings = null) where T : class
        {
            jsonSerializerSettings ??= defaultSettings;
            return input
                .Where(payload => payload.Path == path)
                .Decode<T>(jsonSerializerSettings);
        }
        
        public static IObservable<T> Decode<T>(this IObservable<BridgeMessage> input, 
            JsonSerializerSettings jsonSerializerSettings = null) where T : class
        {
            jsonSerializerSettings ??= defaultSettings;
            return input
                .Select(payload =>
                {
                    try
                    {
                        return JsonConvert.DeserializeObject<T>(payload.Content, jsonSerializerSettings);
                    }
                    catch (Exception e)
                    {
                        Debug.LogError($"Decode to {typeof(T).Name} error {e.Message} content {payload.Content}");
                        return null;
                    }
                })
                .Where(decoded => decoded != null);
        }
    }
}