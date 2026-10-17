# -*- coding: utf-8 -*-
# Перенос ручного патча permission_handler_android 10.3.6: удаление устаревшего
# PluginRegistry.Registrar API (удалён из свежих Flutter; иначе compileReleaseJavaWithJavac
# падает с "cannot find symbol"). Скрипт идемпотентен: повторный запуск безопасен.
import io, sys, glob, os

p = sys.argv[1] if len(sys.argv) > 1 else None
if not p:
    cands = glob.glob(os.path.expanduser('~/.pub-cache/hosted/pub.dev/permission_handler_android-10.3.6/android/src/main/java/com/baseflow/permissionhandler/PermissionHandlerPlugin.java'))
    if not cands:
        print('файл плагина не найден'); sys.exit(1)
    p = cands[0]

src = io.open(p, encoding='utf-8').read()
orig_len = len(src)

MARK_A = '@Nullable private io.flutter.plugin.common.PluginRegistry.Registrar pluginRegistrar;'
MARK_B = 'plugin.pluginRegistrar = registrar;'
MARK_C = 'this.pluginRegistrar != null'

if (MARK_A not in src) and (MARK_B not in src) and (MARK_C not in src):
    print('файл уже пропатчен — ничего не делаем (%d байт)' % orig_len)
    sys.exit(0)

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

applied = []
for name, old, new in (('A', A, ''), ('B', B_HEAD, ''), ('C', C, C_new)):
    if old in src:
        src = src.replace(old, new)
        applied.append(name)
    else:
        print('патч %s: якорь не найден!' % name); sys.exit(2)

io.open(p, 'w', encoding='utf-8', newline='\n').write(src)
print('патчи применены: %s | %d -> %d байт' % (','.join(applied), orig_len, len(src)))
