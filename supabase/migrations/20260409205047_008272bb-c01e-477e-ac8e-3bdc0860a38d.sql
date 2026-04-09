
-- Create app_role enum
CREATE TYPE public.app_role AS ENUM ('owner', 'admin', 'courier', 'office');

-- Profiles table
CREATE TABLE public.profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  full_name TEXT DEFAULT '',
  phone TEXT DEFAULT '',
  login_code TEXT DEFAULT '',
  salary NUMERIC DEFAULT 0,
  office_id UUID,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Authenticated users can view profiles" ON public.profiles FOR SELECT TO authenticated USING (true);
CREATE POLICY "Users can update own profile" ON public.profiles FOR UPDATE TO authenticated USING (auth.uid() = id);
CREATE POLICY "Service can insert profiles" ON public.profiles FOR INSERT TO authenticated WITH CHECK (auth.uid() = id);

-- Auto-create profile on signup
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  INSERT INTO public.profiles (id, full_name) VALUES (NEW.id, COALESCE(NEW.raw_user_meta_data->>'full_name', ''));
  RETURN NEW;
END;
$$;
CREATE TRIGGER on_auth_user_created AFTER INSERT ON auth.users FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- User roles (NO RLS policies referencing has_role yet)
CREATE TABLE public.user_roles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  role app_role NOT NULL,
  created_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(user_id, role)
);
ALTER TABLE public.user_roles ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Authenticated can view roles" ON public.user_roles FOR SELECT TO authenticated USING (true);

-- has_role function MUST be created AFTER user_roles table exists
CREATE OR REPLACE FUNCTION public.has_role(_user_id UUID, _role app_role)
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = _user_id AND role = _role);
$$;

-- Now add management policy for user_roles using has_role
CREATE POLICY "Owners/admins can manage roles" ON public.user_roles FOR ALL TO authenticated USING (public.has_role(auth.uid(), 'owner'::app_role) OR public.has_role(auth.uid(), 'admin'::app_role));

-- User permissions
CREATE TABLE public.user_permissions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  section TEXT NOT NULL,
  permission TEXT NOT NULL DEFAULT 'edit',
  created_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(user_id, section)
);
ALTER TABLE public.user_permissions ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Authenticated can view permissions" ON public.user_permissions FOR SELECT TO authenticated USING (true);
CREATE POLICY "Owners/admins can manage permissions" ON public.user_permissions FOR ALL TO authenticated USING (public.has_role(auth.uid(), 'owner'::app_role) OR public.has_role(auth.uid(), 'admin'::app_role));

-- Offices
CREATE TABLE public.offices (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  specialty TEXT DEFAULT '',
  owner_name TEXT DEFAULT '',
  owner_phone TEXT DEFAULT '',
  address TEXT DEFAULT '',
  notes TEXT DEFAULT '',
  can_add_orders BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE public.offices ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Authenticated can view offices" ON public.offices FOR SELECT TO authenticated USING (true);
CREATE POLICY "Authenticated can manage offices" ON public.offices FOR ALL TO authenticated USING (true);

ALTER TABLE public.profiles ADD CONSTRAINT profiles_office_id_fkey FOREIGN KEY (office_id) REFERENCES public.offices(id) ON DELETE SET NULL;

-- Companies
CREATE TABLE public.companies (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  agreement_price NUMERIC DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Authenticated can manage companies" ON public.companies FOR ALL TO authenticated USING (true);

-- Products
CREATE TABLE public.products (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  quantity INTEGER DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Authenticated can manage products" ON public.products FOR ALL TO authenticated USING (true);

-- Order statuses
CREATE TABLE public.order_statuses (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  color TEXT DEFAULT '#666',
  sort_order INTEGER DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE public.order_statuses ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Authenticated can manage statuses" ON public.order_statuses FOR ALL TO authenticated USING (true);

INSERT INTO public.order_statuses (name, color, sort_order) VALUES
  ('جديد', '#3b82f6', 0),
  ('قيد التوصيل', '#f59e0b', 1),
  ('تم التسليم', '#22c55e', 2),
  ('تسليم جزئي', '#8b5cf6', 3),
  ('مؤجل', '#6b7280', 4),
  ('رفض ودفع شحن', '#ef4444', 5),
  ('رفض ولم يدفع شحن', '#dc2626', 6),
  ('استلم ودفع نص الشحن', '#f97316', 7),
  ('تهرب', '#991b1b', 8),
  ('ملغي', '#374151', 9),
  ('لم يرد', '#9ca3af', 10),
  ('لايرد', '#d1d5db', 11);

-- Orders
CREATE TABLE public.orders (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tracking_id TEXT,
  barcode TEXT,
  customer_name TEXT NOT NULL,
  customer_phone TEXT DEFAULT '',
  customer_code TEXT DEFAULT '',
  product_name TEXT DEFAULT 'بدون منتج',
  product_id UUID REFERENCES public.products(id) ON DELETE SET NULL,
  quantity INTEGER DEFAULT 1,
  price NUMERIC DEFAULT 0,
  delivery_price NUMERIC DEFAULT 0,
  color TEXT DEFAULT '',
  size TEXT DEFAULT '',
  address TEXT DEFAULT '',
  notes TEXT DEFAULT '',
  priority TEXT DEFAULT 'normal',
  status_id UUID REFERENCES public.order_statuses(id) ON DELETE SET NULL,
  office_id UUID REFERENCES public.offices(id) ON DELETE SET NULL,
  courier_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  company_id UUID REFERENCES public.companies(id) ON DELETE SET NULL,
  is_closed BOOLEAN DEFAULT false,
  is_courier_closed BOOLEAN DEFAULT false,
  is_settled BOOLEAN DEFAULT false,
  shipping_paid NUMERIC DEFAULT 0,
  partial_amount NUMERIC DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Authenticated can manage orders" ON public.orders FOR ALL TO authenticated USING (true);

CREATE OR REPLACE FUNCTION public.generate_barcode()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.barcode IS NULL OR NEW.barcode = '' THEN
    NEW.barcode := 'SL' || LPAD(FLOOR(RANDOM() * 999999999)::TEXT, 9, '0');
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER set_barcode BEFORE INSERT ON public.orders FOR EACH ROW EXECUTE FUNCTION public.generate_barcode();

-- Order notes
CREATE TABLE public.order_notes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id UUID NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
  user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  note TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE public.order_notes ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Authenticated can manage notes" ON public.order_notes FOR ALL TO authenticated USING (true);

-- Diaries
CREATE TABLE public.diaries (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  office_id UUID NOT NULL REFERENCES public.offices(id) ON DELETE CASCADE,
  diary_date DATE DEFAULT CURRENT_DATE,
  diary_number SERIAL,
  is_closed BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE public.diaries ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Authenticated can manage diaries" ON public.diaries FOR ALL TO authenticated USING (true);

-- Diary orders
CREATE TABLE public.diary_orders (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  diary_id UUID NOT NULL REFERENCES public.diaries(id) ON DELETE CASCADE,
  order_id UUID NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
  status TEXT DEFAULT 'pending',
  n_column TEXT DEFAULT '',
  manual_total_amount NUMERIC DEFAULT 0,
  manual_shipping_amount NUMERIC DEFAULT 0,
  manual_shipping_diff NUMERIC DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE public.diary_orders ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Authenticated can manage diary orders" ON public.diary_orders FOR ALL TO authenticated USING (true);

-- Courier collections
CREATE TABLE public.courier_collections (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  courier_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  order_id UUID REFERENCES public.orders(id) ON DELETE CASCADE,
  amount NUMERIC DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE public.courier_collections ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Authenticated can manage collections" ON public.courier_collections FOR ALL TO authenticated USING (true);

-- Courier bonuses
CREATE TABLE public.courier_bonuses (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  courier_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  amount NUMERIC DEFAULT 0,
  reason TEXT DEFAULT '',
  created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE public.courier_bonuses ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Authenticated can manage bonuses" ON public.courier_bonuses FOR ALL TO authenticated USING (true);

-- Courier locations
CREATE TABLE public.courier_locations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  courier_id UUID NOT NULL UNIQUE REFERENCES auth.users(id) ON DELETE CASCADE,
  latitude NUMERIC,
  longitude NUMERIC,
  accuracy NUMERIC,
  updated_at TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE public.courier_locations ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Authenticated can manage locations" ON public.courier_locations FOR ALL TO authenticated USING (true);

-- Delivery prices
CREATE TABLE public.delivery_prices (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  office_id UUID REFERENCES public.offices(id) ON DELETE CASCADE,
  governorate TEXT NOT NULL,
  price NUMERIC DEFAULT 0,
  pickup_price NUMERIC DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE public.delivery_prices ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Authenticated can manage prices" ON public.delivery_prices FOR ALL TO authenticated USING (true);

-- Office payments
CREATE TABLE public.office_payments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  office_id UUID NOT NULL REFERENCES public.offices(id) ON DELETE CASCADE,
  amount NUMERIC DEFAULT 0,
  type TEXT DEFAULT 'advance',
  notes TEXT DEFAULT '',
  created_at TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE public.office_payments ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Authenticated can manage office payments" ON public.office_payments FOR ALL TO authenticated USING (true);

-- Company payments
CREATE TABLE public.company_payments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  amount NUMERIC DEFAULT 0,
  notes TEXT DEFAULT '',
  created_at TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE public.company_payments ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Authenticated can manage company payments" ON public.company_payments FOR ALL TO authenticated USING (true);

-- Office daily closings
CREATE TABLE public.office_daily_closings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  office_id UUID NOT NULL REFERENCES public.offices(id) ON DELETE CASCADE,
  closing_date DATE NOT NULL,
  data_json JSONB DEFAULT '[]',
  pickup_rate NUMERIC DEFAULT 0,
  is_locked BOOLEAN DEFAULT false,
  is_closed BOOLEAN DEFAULT false,
  prevent_add BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(office_id, closing_date)
);
ALTER TABLE public.office_daily_closings ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Authenticated can manage closings" ON public.office_daily_closings FOR ALL TO authenticated USING (true);

-- Advances
CREATE TABLE public.advances (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  amount NUMERIC DEFAULT 0,
  type TEXT DEFAULT 'advance',
  notes TEXT DEFAULT '',
  created_at TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE public.advances ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Authenticated can manage advances" ON public.advances FOR ALL TO authenticated USING (true);

-- Expenses
CREATE TABLE public.expenses (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  expense_name TEXT NOT NULL,
  amount NUMERIC DEFAULT 0,
  category TEXT DEFAULT 'أخرى',
  notes TEXT DEFAULT '',
  expense_date DATE DEFAULT CURRENT_DATE,
  office_id UUID REFERENCES public.offices(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE public.expenses ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Authenticated can manage expenses" ON public.expenses FOR ALL TO authenticated USING (true);

-- Cash flow entries
CREATE TABLE public.cash_flow_entries (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  type TEXT DEFAULT 'inside',
  amount NUMERIC DEFAULT 0,
  reason TEXT DEFAULT '',
  notes TEXT DEFAULT '',
  entry_date DATE DEFAULT CURRENT_DATE,
  office_id UUID REFERENCES public.offices(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE public.cash_flow_entries ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Authenticated can manage cash flow" ON public.cash_flow_entries FOR ALL TO authenticated USING (true);

-- Activity logs
CREATE TABLE public.activity_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  action TEXT NOT NULL,
  details JSONB DEFAULT '{}',
  created_at TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE public.activity_logs ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Authenticated can view logs" ON public.activity_logs FOR SELECT TO authenticated USING (true);
CREATE POLICY "Authenticated can insert logs" ON public.activity_logs FOR INSERT TO authenticated WITH CHECK (true);

CREATE OR REPLACE FUNCTION public.log_activity(_action TEXT, _details JSONB DEFAULT '{}')
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  INSERT INTO public.activity_logs (user_id, action, details) VALUES (auth.uid(), _action, _details);
END;
$$;

-- Messages
CREATE TABLE public.messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  sender_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  receiver_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  message TEXT NOT NULL,
  is_read BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can view own messages" ON public.messages FOR SELECT TO authenticated USING (auth.uid() = sender_id OR auth.uid() = receiver_id);
CREATE POLICY "Users can send messages" ON public.messages FOR INSERT TO authenticated WITH CHECK (auth.uid() = sender_id);
CREATE POLICY "Users can update own messages" ON public.messages FOR UPDATE TO authenticated USING (auth.uid() = receiver_id);

-- App settings
CREATE TABLE public.app_settings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  key TEXT NOT NULL UNIQUE,
  value TEXT DEFAULT '',
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE public.app_settings ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Authenticated can view settings" ON public.app_settings FOR SELECT TO authenticated USING (true);
CREATE POLICY "Owners/admins can manage settings" ON public.app_settings FOR ALL TO authenticated USING (public.has_role(auth.uid(), 'owner'::app_role) OR public.has_role(auth.uid(), 'admin'::app_role));

-- Updated_at trigger function
CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

CREATE TRIGGER update_profiles_updated_at BEFORE UPDATE ON public.profiles FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
CREATE TRIGGER update_offices_updated_at BEFORE UPDATE ON public.offices FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
CREATE TRIGGER update_orders_updated_at BEFORE UPDATE ON public.orders FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
CREATE TRIGGER update_app_settings_updated_at BEFORE UPDATE ON public.app_settings FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

ALTER PUBLICATION supabase_realtime ADD TABLE public.messages;
