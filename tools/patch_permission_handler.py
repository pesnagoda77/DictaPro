# -*- coding: utf-8 -*-
# Перенос ручного патча permission_handler_android 10.3.6: удаление устаревшего
# PluginRegistry.Registrar API (удалён из свежих Flutter; иначе compileReleaseJavaWithJavac
# падает с "cannot find symbol" в PermissionHandlerPlugin.java:28/47).
import io, sys

p = sys.argv[1] if len(sys.argv) > 1 else None
if not p:
    import glob, os
    cands = glob.glob(os.path.expanduser('~/.pub-cache/hosted/pub.dev/permission_handler_android-10.3.6/android/src/main/java/com/baseflow/permissionhandler/PermissionHandlerPlugin.java'))
    if not cands:
        print('файл плагина не найден'); sys.exit(1)
    p = cands[0]

src = io.open(p, encoding='utf-8').read()
orig_len = len(src)

A = '''    @SuppressWarnings("deprecation")
    @Nullable private io.flutter.plugin.common.PluginRegistry.Registrar pluginRegistrar;

'''
B_HEAD = '''    /**
     * Registers a plugin implementation that uses the stable {@code io.flutter.plugin.common}
     * package.
     *
     * <p>Calling this automatically initializes the plugin. However plugins initialized this way
     * won't react to changes in activity or context, unlike {@link PermissionHandlerPlugin}.
     */
    @SuppressWarnings("deprecation")
    public static void registerWith(io.flutter.plugin.common.PluginRegistry.Registrar registrar) {
        final PermissionHandlerPlugin plugin = new PermissionHandlerPlugin();

        plugin.pluginRegistrar = registrar;
        plugin.registerListeners();

        plugin.startListening(registrar.context(), registrar.messenger());

        if (registrar.activeContext() instanceof Activity) {
            plugin.startListeningToActivity(
                registrar.activity()
            );
        }
    }

'''
C = '''        if (this.pluginRegistrar != null) {
            this.pluginRegistrar.addActivityResultListener(this.permissionManager);
            this.pluginRegistrar.addRequestPermissionsResultListener(this.permissionManager);
        } else if (pluginBinding != null) {'''
C_new = '''        if (pluginBinding != null) {'''

for name, old, new in (('A', A, ''), ('B', B_HEAD, ''), ('C', C, C_new)):
    if name in ('A', 'B') and old in src:
        src = src.replace(old, new)
        print('патч', name, 'применён')
    elif name == 'C' and old in src:
        src = src.replace(old, C_new)
        print('патч', name, 'применён')
    else:
        # допускаем повторный запуск: если уже пропатчено — проверить
        if name == 'A' and 'PluginRegistry.Registrar pluginRegistrar' not in src:
            print('патч', name, 'уже/не нужен')
        elif name == 'B' and 'registerWith(io.flutter.plugin.common.PluginRegistry' not in src:
            print('патч', name, 'уже/не нужен')
        elif name == 'C' and 'this.pluginRegistrar' not in src:
            print('патч', name, 'уже/не нужен')
        else:
            print('патч', name, 'НЕ НАЙДЕН якорь!'); sys.exit(2)

io.open(p, 'w', encoding='utf-8', newline='\n').write(src)
print('готово: %d -> %d байт' % (orig_len, len(src)))
