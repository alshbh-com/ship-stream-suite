import { useEffect, useRef } from 'react';
import { supabase } from '@/integrations/supabase/client';

const STORAGE_KEY = 'courier_last_location';
const SEND_INTERVAL = 15000; // 15 seconds

/**
 * Hook that sends the courier's GPS location to the DB every 15 seconds.
 * Always keeps courier "online" by continuously updating updated_at,
 * even if GPS is turned off (uses last cached position).
 */
export function useCourierLocation(userId: string | undefined) {
  const watchIdRef = useRef<number | null>(null);
  const intervalRef = useRef<ReturnType<typeof setInterval> | null>(null);
  const latestPos = useRef<{ lat: number; lng: number; accuracy: number } | null>(null);

  useEffect(() => {
    if (!userId) return;

    // Restore last known location from localStorage
    try {
      const saved = localStorage.getItem(STORAGE_KEY);
      if (saved) {
        latestPos.current = JSON.parse(saved);
      }
    } catch {}

    // Default fallback position (Cairo) if no cached position exists
    const getPosition = () => latestPos.current || { lat: 30.0444, lng: 31.2357, accuracy: 99999 };

    const sendLocation = async () => {
      const pos = getPosition();
      try {
        await supabase.from('courier_locations').upsert({
          courier_id: userId,
          latitude: pos.lat,
          longitude: pos.lng,
          accuracy: pos.accuracy,
          updated_at: new Date().toISOString(),
        }, { onConflict: 'courier_id' });
      } catch (e) {
        console.warn('Failed to send location:', e);
      }
    };

    if (navigator.geolocation) {
      watchIdRef.current = navigator.geolocation.watchPosition(
        (position) => {
          const loc = {
            lat: position.coords.latitude,
            lng: position.coords.longitude,
            accuracy: position.coords.accuracy,
          };
          latestPos.current = loc;
          try {
            localStorage.setItem(STORAGE_KEY, JSON.stringify(loc));
          } catch {}
        },
        (err) => {
          console.warn('Geolocation error:', err.message);
          // Continue sending cached location
        },
        { enableHighAccuracy: true, maximumAge: 10000, timeout: 15000 }
      );
    }

    // Send immediately, then every 15 seconds
    sendLocation();
    intervalRef.current = setInterval(sendLocation, SEND_INTERVAL);

    // Also handle visibility change - send when app comes back to foreground
    const handleVisibility = () => {
      if (document.visibilityState === 'visible') {
        sendLocation();
      }
    };
    document.addEventListener('visibilitychange', handleVisibility);

    return () => {
      if (watchIdRef.current !== null) navigator.geolocation.clearWatch(watchIdRef.current);
      if (intervalRef.current) clearInterval(intervalRef.current);
      document.removeEventListener('visibilitychange', handleVisibility);
    };
  }, [userId]);
}
