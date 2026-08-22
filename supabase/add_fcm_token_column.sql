-- Add fcm_token column to profiles table for Firebase Cloud Messaging.
-- Run this in the Supabase SQL Editor.

-- Add the column (safe to run multiple times — idempotent).
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'profiles' AND column_name = 'fcm_token'
  ) THEN
    ALTER TABLE public.profiles ADD COLUMN fcm_token text;
  END IF;
END $$;

-- Create an index for fast token lookups (server-side push targeting).
CREATE INDEX IF NOT EXISTS idx_profiles_fcm_token ON public.profiles (fcm_token) WHERE fcm_token IS NOT NULL;

-- Allow users to update their own fcm_token via the API (RLS policy).
-- The existing update policy on profiles should already cover this,
-- but if you have restrictive policies, add:
-- CREATE POLICY "Users can update own fcm_token" ON public.profiles
--   FOR UPDATE USING (auth.uid() = id)
--   WITH CHECK (auth.uid() = id);
