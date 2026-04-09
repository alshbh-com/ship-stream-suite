
-- Create a sequence for barcodes
CREATE SEQUENCE IF NOT EXISTS public.barcode_seq START WITH 1;

-- Replace the barcode trigger function with sequential logic
CREATE OR REPLACE FUNCTION public.generate_barcode()
RETURNS TRIGGER LANGUAGE plpgsql SET search_path = public AS $$
BEGIN
  IF NEW.barcode IS NULL OR NEW.barcode = '' THEN
    NEW.barcode := nextval('public.barcode_seq')::TEXT;
  END IF;
  RETURN NEW;
END;
$$;
