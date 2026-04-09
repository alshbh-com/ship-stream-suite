
-- Add missing columns to diaries
ALTER TABLE public.diaries ADD COLUMN IF NOT EXISTS lock_status_updates BOOLEAN DEFAULT false;
ALTER TABLE public.diaries ADD COLUMN IF NOT EXISTS prevent_new_orders BOOLEAN DEFAULT false;
ALTER TABLE public.diaries ADD COLUMN IF NOT EXISTS is_archived BOOLEAN DEFAULT false;

-- Add missing columns to profiles for couriers
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS address TEXT DEFAULT '';
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS coverage_areas TEXT DEFAULT '';
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS notes TEXT DEFAULT '';
