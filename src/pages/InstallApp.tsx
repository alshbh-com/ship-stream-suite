import { useState, useEffect } from 'react';
import { Card, CardContent } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Download, Smartphone, CheckCircle, Globe, Share } from 'lucide-react';

interface BeforeInstallPromptEvent extends Event {
  prompt(): Promise<void>;
  userChoice: Promise<{ outcome: 'accepted' | 'dismissed' }>;
}

export default function InstallApp() {
  const [deferredPrompt, setDeferredPrompt] = useState<BeforeInstallPromptEvent | null>(null);
  const [installed, setInstalled] = useState(false);
  const [isStandalone, setIsStandalone] = useState(false);

  useEffect(() => {
    setIsStandalone(
      window.matchMedia('(display-mode: standalone)').matches ||
      (window.navigator as any).standalone === true
    );

    const handler = (e: Event) => {
      e.preventDefault();
      setDeferredPrompt(e as BeforeInstallPromptEvent);
    };

    window.addEventListener('beforeinstallprompt', handler);
    window.addEventListener('appinstalled', () => setInstalled(true));

    return () => window.removeEventListener('beforeinstallprompt', handler);
  }, []);

  const handleInstall = async () => {
    if (!deferredPrompt) return;
    await deferredPrompt.prompt();
    const { outcome } = await deferredPrompt.userChoice;
    if (outcome === 'accepted') setInstalled(true);
    setDeferredPrompt(null);
  };

  const isIOS = /iPad|iPhone|iPod/.test(navigator.userAgent);
  const isAndroid = /Android/.test(navigator.userAgent);

  if (isStandalone) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-background p-4" dir="rtl">
        <Card className="max-w-sm w-full">
          <CardContent className="p-8 text-center space-y-4">
            <CheckCircle className="h-16 w-16 text-green-500 mx-auto" />
            <h1 className="text-2xl font-bold">التطبيق مثبّت بالفعل!</h1>
            <p className="text-muted-foreground">أنت تستخدم التطبيق الآن كتطبيق مستقل.</p>
            <Button className="w-full" onClick={() => window.location.href = '/'}>
              الذهاب للصفحة الرئيسية
            </Button>
          </CardContent>
        </Card>
      </div>
    );
  }

  return (
    <div className="min-h-screen flex items-center justify-center bg-background p-4" dir="rtl">
      <Card className="max-w-sm w-full">
        <CardContent className="p-6 space-y-6 text-center">
          <div className="mx-auto w-20 h-20 rounded-2xl overflow-hidden shadow-lg">
            <img src="/pwa-icon-512.png" alt="Star Logistics" className="w-full h-full object-cover" />
          </div>
          <div>
            <h1 className="text-2xl font-bold">تثبيت التطبيق</h1>
            <p className="text-muted-foreground text-sm mt-1">
              ثبّت التطبيق على هاتفك للحصول على تجربة أفضل ودعم كامل للموقع (GPS).
            </p>
          </div>

          {installed ? (
            <div className="space-y-3">
              <CheckCircle className="h-12 w-12 text-green-500 mx-auto" />
              <p className="font-bold text-green-600">تم تثبيت التطبيق بنجاح!</p>
              <p className="text-sm text-muted-foreground">افتح التطبيق من شاشتك الرئيسية.</p>
            </div>
          ) : deferredPrompt ? (
            <Button size="lg" className="w-full gap-2 text-base" onClick={handleInstall}>
              <Download className="h-5 w-5" />
              تثبيت التطبيق الآن
            </Button>
          ) : (
            <div className="space-y-4">
              {isIOS && (
                <div className="bg-muted rounded-lg p-4 text-right space-y-2">
                  <p className="font-bold flex items-center gap-2 justify-end">
                    <Smartphone className="h-4 w-4" /> طريقة التثبيت على iPhone
                  </p>
                  <p className="text-sm">1. افتح هذا الرابط في متصفح <strong>Safari</strong></p>
                  <p className="text-sm flex items-center gap-1">2. اضغط على زر المشاركة <Share className="h-4 w-4 inline" /></p>
                  <p className="text-sm">3. اختر <strong>"إضافة إلى الشاشة الرئيسية"</strong></p>
                  <p className="text-sm">4. اضغط <strong>"إضافة"</strong></p>
                </div>
              )}
              {isAndroid && (
                <div className="bg-muted rounded-lg p-4 text-right space-y-2">
                  <p className="font-bold flex items-center gap-2 justify-end">
                    <Smartphone className="h-4 w-4" /> طريقة التثبيت على Android
                  </p>
                  <p className="text-sm">1. افتح هذا الرابط في متصفح <strong>Chrome</strong></p>
                  <p className="text-sm">2. اضغط على <strong>⋮</strong> (القائمة) أعلى المتصفح</p>
                  <p className="text-sm">3. اختر <strong>"تثبيت التطبيق"</strong> أو <strong>"إضافة إلى الشاشة"</strong></p>
                </div>
              )}
              {!isIOS && !isAndroid && (
                <div className="bg-muted rounded-lg p-4 text-right space-y-2">
                  <p className="font-bold flex items-center gap-2 justify-end">
                    <Globe className="h-4 w-4" /> طريقة التثبيت
                  </p>
                  <p className="text-sm">افتح الرابط في متصفح Chrome أو Edge واختر "تثبيت التطبيق" من القائمة.</p>
                </div>
              )}
            </div>
          )}

          <div className="border-t pt-4">
            <p className="text-xs text-muted-foreground">
              <strong>لماذا تثبيت التطبيق من المتصفح؟</strong>
              <br />
              التطبيق المثبّت من المتصفح يدعم صلاحية الموقع (GPS) بشكل كامل بدلاً من تطبيق WebView.
            </p>
          </div>
        </CardContent>
      </Card>
    </div>
  );
}