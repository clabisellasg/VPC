{{flutter_js}}
{{flutter_build_config}}

(async () => {
  // M19 intentionally has no Web offline service worker. Remove any obsolete
  // Flutter worker retained by an earlier installation before bootstrapping.
  if ('serviceWorker' in navigator) {
    try {
      const registrations = await navigator.serviceWorker.getRegistrations();
      await Promise.all(registrations.map((registration) => {
        const worker = registration.active || registration.waiting || registration.installing;
        if (!worker) return Promise.resolve(false);
        const path = new URL(worker.scriptURL).pathname;
        return path.endsWith('/flutter_service_worker.js')
          ? registration.unregister()
          : Promise.resolve(false);
      }));
    } catch (_) {
      // Startup remains available if service-worker inspection is blocked.
    }
  }

  // iOS WebKit can briefly composite a stale WebGL canvas while traversing
  // browser history. Keep CanvasKit, but use its CPU surface on iPhone/iPad so
  // Safari and Home Screen navigation repaint from the current Flutter frame.
  const iosWebKit = /iPad|iPhone|iPod/.test(navigator.userAgent) ||
    (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
  await _flutter.loader.load({
    config: {canvasKitForceCpuOnly: iosWebKit},
  });
})();
