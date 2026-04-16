import { useEffect, useRef } from 'react';
import { supabase } from '@/integrations/supabase/client';

const STORAGE_KEY = 'courier_last_location';

/**
 * Hook that sends the courier's GPS location to the DB every 30 seconds.
 * Saves last known location to localStorage so it persists even if GPS is turned off.
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

    const sendLocation = async () => {
      const pos = latestPos.current;
      if (!pos) return;
      await supabase.from('courier_locations').upsert({
        courier_id: userId,
        latitude: pos.lat,
        longitude: pos.lng,
        accuracy: pos.accuracy,
        updated_at: new Date().toISOString(),
      }, { onConflict: 'courier_id' });
    };

    if (navigator.geolocation) {
      // Watch position continuously
      watchIdRef.current = navigator.geolocation.watchPosition(
        (position) => {
          const loc = {
            lat: position.coords.latitude,
            lng: position.coords.longitude,
            accuracy: position.coords.accuracy,
          };
          latestPos.current = loc;
          // Save to localStorage for persistence
          try {
            localStorage.setItem(STORAGE_KEY, JSON.stringify(loc));
          } catch {}
        },
        (err) => {
          console.warn('Geolocation error:', err.message);
          // Still send last known location even if GPS fails
        },
        { enableHighAccuracy: true, maximumAge: 10000, timeout: 15000 }
      );
    }

    // Send to DB every 30 seconds (even if GPS is off, sends last known)
    sendLocation();
    intervalRef.current = setInterval(sendLocation, 30000);

    return () => {
      if (watchIdRef.current !== null) navigator.geolocation.clearWatch(watchIdRef.current);
      if (intervalRef.current) clearInterval(intervalRef.current);
    };
  }, [userId]);
}
