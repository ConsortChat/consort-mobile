package chat.consort.mobile

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import java.lang.reflect.Constructor

/**
 * A Flutter plugin that just wraps ZulipPlugin.
 *
 * For background, see comment in the `pubspec.yaml` file
 * of this `zulip_plugin` package.
 */
class ZulipShimPlugin : FlutterPlugin, ActivityAware {
    private val plugin: FlutterPlugin = pluginConstructor.newInstance()

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        plugin.onAttachedToEngine(binding)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        plugin.onDetachedFromEngine(binding)
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        (plugin as ActivityAware).onAttachedToActivity(binding)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        (plugin as ActivityAware).onDetachedFromActivityForConfigChanges()
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        (plugin as ActivityAware).onReattachedToActivityForConfigChanges(binding)
    }

    override fun onDetachedFromActivity() {
        (plugin as ActivityAware).onDetachedFromActivity()
    }

    companion object {
        private val pluginConstructor: Constructor<FlutterPlugin> by lazy {
            // We can't give this shim a compile-time dependency on ZulipPlugin
            // because that lives in the main application package, which depends on
            // this `zulip_plugin` package.
            //
            // (The root cause here is that the purpose of this shim plugin is to be
            // visible to the `flutter` tool so that the tool includes it in
            // GeneratedPluginRegistrant, and the structure the `flutter` tool
            // expects plugins to have is that the plugin corresponds to a package
            // which the application depends on.)
            //
            // Lacking a compile-time dependency, we instead use reflection
            // to find ZulipPlugin.
            val pluginClass = Class.forName("chat.consort.mobile.ZulipPlugin")
            @Suppress("UNCHECKED_CAST")
            (pluginClass as Class<FlutterPlugin>).getConstructor()
        }
    }
}
