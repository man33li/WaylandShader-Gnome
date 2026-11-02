import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import GIRepository from 'gi://GIRepository?version=3.0';

import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

const EFFECT_NAME = 'waylandshader-gnome';
const INTERFACE = 'org.waylandshader.Effect';
const XML = `<node>
  <interface name="${INTERFACE}">
    <method name="status"><arg type="s" direction="out"/></method>
    <method name="loadPreset"><arg type="s" direction="in"/><arg type="b" direction="out"/></method>
    <method name="setEnabled"><arg type="b" direction="in"/><arg type="b" direction="out"/></method>
    <method name="setParameter"><arg type="s" direction="in"/><arg type="d" direction="in"/><arg type="b" direction="out"/></method>
    <method name="setOutputShaderEnabled"><arg type="s" direction="in"/><arg type="b" direction="in"/><arg type="b" direction="out"/></method>
    <method name="setOutputColorEnabled"><arg type="s" direction="in"/><arg type="b" direction="in"/><arg type="b" direction="out"/></method>
    <method name="setOutputGamma"><arg type="s" direction="in"/><arg type="d" direction="in"/><arg type="b" direction="out"/></method>
    <method name="setOutputSaturation"><arg type="s" direction="in"/><arg type="d" direction="in"/><arg type="b" direction="out"/></method>
    <method name="profiles"><arg type="s" direction="out"/></method>
    <method name="saveProfile"><arg type="s" direction="in"/><arg type="b" direction="out"/></method>
    <method name="loadProfile"><arg type="s" direction="in"/><arg type="b" direction="out"/></method>
    <method name="deleteProfile"><arg type="s" direction="in"/><arg type="b" direction="out"/></method>
    <method name="setDefaultProfile"><arg type="s" direction="in"/><arg type="b" direction="out"/></method>
    <signal name="statusChanged"><arg type="s"/></signal>
  </interface>
</node>`;

export default class WaylandShaderExtension extends Extension {
    async enable() {
        this._closing = false;
        this._settingsLoaded = false;
        this._signals = [];
        this._inhibited = false;
        this._attached = false;
        this._lastSaved = null;
        try {
            const nativeDirectory = GLib.build_filenamev([this.path, 'native']);
            const repository = GIRepository.Repository.dup_default();
            repository.prepend_search_path(nativeDirectory);
            repository.prepend_library_path(nativeDirectory);
            const {default: WaylandShader} = await import('gi://WaylandShader?version=1.0');
            if (this._closing)
                return;
            this._settings = this.getSettings();
            this._effect = WaylandShader.Effect.new();
            this._connect(this._effect, 'status-changed', (_effect, json) => this._onStatus(json));
            this._connect(global.backend.get_monitor_manager(), 'monitors-changing', () => {
                this._effect.reset_history();
                this._effect.set_outputs('[]');
            });
            this._connect(Main.layoutManager, 'monitors-changed', () => this._updateOutputs());
            this._connect(Main.sessionMode, 'updated', () => {
                this._effect.reset_history();
                global.stage.queue_redraw();
            });
            this._connect(global, 'shutdown', () => this._cleanup());

            if (global.stage.get_effect(EFFECT_NAME))
                throw new Error('Another WaylandShader effect is already attached to the stage.');
            global.stage.add_effect_with_name(EFFECT_NAME, this._effect);
            this._attached = true;
            this._updateOutputs();
            let saved = this._settings.get_string('configuration');
            const preferred = this._settings.get_string('default-profile');
            const stored = this._readProfiles();
            const profile = Object.hasOwn(stored, preferred) ? stored[preferred] : undefined;
            if (profile) {
                try {
                    saved = this._withProfile(saved, profile);
                } catch (error) {
                    console.error(`WaylandShader: could not apply default profile ${preferred}`, error);
                }
            }
            if (saved)
                this._effect.import_settings(saved);
            this._settingsLoaded = true;
            this._dbus = Gio.DBusExportedObject.wrapJSObject(XML, this);
            this._dbus.export(Gio.DBus.session, '/WaylandShader');
            this._onStatus(this._effect.get_status());
            global.stage.queue_redraw();
        } catch (error) {
            this._cleanup();
            throw error;
        }
    }

    disable() {
        this._cleanup();
    }

    _connect(object, signal, callback) {
        const id = object.connect(signal, (...args) => {
            if (this._closing)
                return;
            try {
                callback(...args);
            } catch (error) {
                console.error(`WaylandShader: ${signal} failed`, error);
            }
        });
        this._signals.push([object, id]);
    }

    _updateOutputs() {
        const manager = global.backend.get_monitor_manager();
        const outputs = [];
        for (const monitor of manager.get_monitors()) {
            const connector = monitor.get_connector();
            const index = manager.get_monitor_for_connector(connector);
            const geometry = Main.layoutManager.monitors.find(item => item.index === index);
            if (!monitor.is_active() || !geometry)
                continue;
            outputs.push({
                id: connector,
                name: connector,
                x: geometry.x,
                y: geometry.y,
                width: geometry.width,
                height: geometry.height,
                scale: global.display.get_monitor_scale(index),
            });
        }
        this._effect.set_outputs(JSON.stringify(outputs));
        this._onStatus(this._effect.get_status());
        global.stage.queue_redraw();
    }

    _saveSettings() {
        if (!this._settingsLoaded || !this._effect || !this._settings)
            return;
        const value = this._effect.export_settings();
        if (value !== this._lastSaved) {
            this._settings.set_string('configuration', value);
            this._lastSaved = value;
        }
    }

    _onStatus(json) {
        if (this._closing)
            return;
        const state = JSON.parse(json);
        // Hold inhibition before the first processed frame, not only after a
        // shaderActive notification. Release it on a fatal rendering failure.
        const requested = !state.error && state.outputs.some(output =>
            output.shaderEnabled && state.preset !== '' ||
            output.colorEnabled && (output.gamma !== 1 || output.saturation !== 1));
        const inhibit = state.enabled && (state.active || state.loading || requested);
        if (inhibit !== this._inhibited) {
            if (inhibit)
                global.compositor.disable_unredirect();
            else
                global.compositor.enable_unredirect();
            this._inhibited = inhibit;
            global.stage.queue_redraw();
        }
        this._saveSettings();
        this._dbus?.emit_signal('statusChanged', new GLib.Variant('(s)', [json]));
    }

    status() {
        return this._effect.get_status();
    }

    _mutate(method, parameters, invocation) {
        if (this._closing || !this._effect) {
            invocation.return_dbus_error('org.waylandshader.Error.Unavailable', 'The GNOME effect is shutting down.');
            return;
        }
        try {
            const accepted = this._effect[method](...parameters);
            this._onStatus(this._effect.get_status());
            invocation.return_value(new GLib.Variant('(b)', [Boolean(accepted)]));
        } catch (error) {
            const message = error.message ?? String(error);
            invocation.return_dbus_error('org.waylandshader.Error.Rejected', message);
        }
    }

    loadPresetAsync(parameters, invocation) {
        this._mutate('load_preset', parameters, invocation);
    }

    setEnabledAsync(parameters, invocation) {
        this._mutate('set_enabled', parameters, invocation);
    }

    setParameterAsync(parameters, invocation) {
        this._mutate('set_parameter', parameters, invocation);
    }

    setOutputShaderEnabledAsync(parameters, invocation) {
        this._mutate('set_output_shader_enabled', parameters, invocation);
    }

    setOutputColorEnabledAsync(parameters, invocation) {
        this._mutate('set_output_color_enabled', parameters, invocation);
    }

    setOutputGammaAsync(parameters, invocation) {
        this._mutate('set_output_gamma', parameters, invocation);
    }

    setOutputSaturationAsync(parameters, invocation) {
        this._mutate('set_output_saturation', parameters, invocation);
    }

    // Profiles: {name: {preset, parameters: {name: value}, outputs: {id: settings}}} in GSettings key `profiles`.
    _readProfiles() {
        try {
            const profiles = JSON.parse(this._settings.get_string('profiles') || '{}');
            return profiles && typeof profiles === 'object' && !Array.isArray(profiles) ? profiles : {};
        } catch (error) {
            console.error('WaylandShader: ignoring malformed saved profiles', error);
            return {};
        }
    }

    // Overlay a profile on a v1 configuration, keeping enablement, recents and other presets' overrides.
    _withProfile(configuration, profile) {
        const base = configuration ? JSON.parse(configuration) : {};
        base.version = 1;
        base.preset = profile.preset ?? '';
        base.parameters = {...base.parameters};
        if (base.preset)
            base.parameters[base.preset] = profile.parameters ?? {};
        base.outputs = {...base.outputs, ...profile.outputs};
        return JSON.stringify(base);
    }

    _profileCall(invocation, name, action) {
        if (this._closing || !this._effect) {
            invocation.return_dbus_error('org.waylandshader.Error.Unavailable', 'The GNOME effect is shutting down.');
            return;
        }
        try {
            if (typeof name !== 'string' || name.trim() === '')
                throw new Error('Profile names must be nonempty.');
            action(this._readProfiles());
            this._onStatus(this._effect.get_status());
            invocation.return_value(new GLib.Variant('(b)', [true]));
        } catch (error) {
            invocation.return_dbus_error('org.waylandshader.Error.Rejected', error.message ?? String(error));
        }
    }

    profiles() {
        const preferred = this._settings.get_string('default-profile');
        const names = Object.keys(this._readProfiles()).sort();
        return JSON.stringify({default: names.includes(preferred) ? preferred : '', profiles: names});
    }

    saveProfileAsync([name], invocation) {
        this._profileCall(invocation, name, profiles => {
            const current = JSON.parse(this._effect.export_settings());
            const preset = current.preset ?? '';
            profiles[name] = {preset, parameters: current.parameters?.[preset] ?? {}, outputs: current.outputs ?? {}};
            this._settings.set_string('profiles', JSON.stringify(profiles));
        });
    }

    loadProfileAsync([name], invocation) {
        this._profileCall(invocation, name, profiles => {
            if (!Object.hasOwn(profiles, name))
                throw new Error(`Unknown profile: ${name}`);
            this._effect.import_settings(this._withProfile(this._effect.export_settings(), profiles[name]));
        });
    }

    deleteProfileAsync([name], invocation) {
        this._profileCall(invocation, name, profiles => {
            if (!Object.hasOwn(profiles, name))
                throw new Error(`Unknown profile: ${name}`);
            delete profiles[name];
            this._settings.set_string('profiles', JSON.stringify(profiles));
            if (this._settings.get_string('default-profile') === name)
                this._settings.set_string('default-profile', '');
        });
    }

    // An empty name clears the default.
    setDefaultProfileAsync([name], invocation) {
        if (name === '') {
            this._settings.set_string('default-profile', '');
            invocation.return_value(new GLib.Variant('(b)', [true]));
            return;
        }
        this._profileCall(invocation, name, profiles => {
            if (!Object.hasOwn(profiles, name))
                throw new Error(`Unknown profile: ${name}`);
            this._settings.set_string('default-profile', name);
        });
    }

    _cleanup() {
        if (this._closing)
            return;
        this._closing = true;
        try {
            this._saveSettings();
        } catch (error) {
            console.error('WaylandShader: could not save settings', error);
        }
        this._dbus?.unexport();
        this._dbus = null;
        for (const [object, id] of this._signals ?? []) {
            try {
                object.disconnect(id);
            } catch (error) {
                console.error('WaylandShader: could not disconnect a signal', error);
            }
        }
        this._signals = [];
        if (this._effect) {
            try {
                this._effect.shutdown();
            } catch (error) {
                console.error('WaylandShader: native shutdown failed', error);
            }
            if (this._attached) {
                global.stage.remove_effect(this._effect);
                this._attached = false;
            }
            this._effect = null;
        }
        if (this._inhibited) {
            global.compositor.enable_unredirect();
            this._inhibited = false;
        }
        this._settings = null;
        global.stage.queue_redraw();
    }
}
