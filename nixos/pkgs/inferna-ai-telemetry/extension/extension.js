import Clutter from 'gi://Clutter';
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import GObject from 'gi://GObject';
import St from 'gi://St';

import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';
import * as Config from 'resource:///org/gnome/shell/misc/config.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as PanelMenu from 'resource:///org/gnome/shell/ui/panelMenu.js';
import * as PopupMenu from 'resource:///org/gnome/shell/ui/popupMenu.js';

const SHELL_VERSION = Number.parseInt(Config.PACKAGE_VERSION.split('.')[0], 10);
const VERTICAL_BOX = SHELL_VERSION >= 51
    ? {orientation: Clutter.Orientation.VERTICAL}
    : {vertical: true};

const USAGE_FILE_PATH = GLib.build_filenamev([
    GLib.get_home_dir(),
    '.cache',
    'inferna-ai',
    'usage.json',
]);

const REFRESH_INTERVAL_SEC = 180;
const BAR_TRACK_WIDTH = 274;

function levelSuffix(pct) {
    if (pct >= 85)
        return 'hot';
    if (pct >= 60)
        return 'warn';
    return 'ok';
}

const InfernaAiIndicator = GObject.registerClass(
class InfernaAiIndicator extends PanelMenu.Button {
    _init(extensionPath) {
        super._init(0.5, 'Inferna AI Telemetry', false);

        this._extensionPath = extensionPath;
        this._collecting = false;
        this._destroyed = false;
        this._timeoutId = 0;
        this._fileMonitor = null;
        this._monitorChangedId = 0;
        this._snapshot = null;

        // Top-bar pill: custom Inferna star/spark icon + highest limit %
        this._barBox = new St.BoxLayout({
            style_class: 'inferna-ai-bar-box',
            y_align: Clutter.ActorAlign.CENTER,
        });

        const iconFile = Gio.File.new_for_path(
            GLib.build_filenamev([extensionPath, 'inferna-ai-symbolic.svg'])
        );
        this._barIcon = new St.Icon({
            gicon: new Gio.FileIcon({file: iconFile}),
            style_class: 'inferna-ai-bar-icon',
            y_align: Clutter.ActorAlign.CENTER,
        });

        this._barLabel = new St.Label({
            text: 'AI',
            style_class: 'inferna-ai-bar-label',
            y_align: Clutter.ActorAlign.CENTER,
        });

        this._barBox.add_child(this._barIcon);
        this._barBox.add_child(this._barLabel);
        this.add_child(this._barBox);

        // Single custom PopupBaseMenuItem holding the Inferna card layout
        this._menuItem = new PopupMenu.PopupBaseMenuItem({
            reactive: false,
            can_focus: false,
        });
        this._popupBox = new St.BoxLayout({
            ...VERTICAL_BOX,
            style_class: 'inferna-ai-popup',
            x_expand: true,
        });
        this._menuItem.add_child(this._popupBox);
        this.menu.addMenuItem(this._menuItem);

        // Watch ~/.cache/inferna-ai/usage.json for atomic updates
        this._setupFileMonitor();
        this._loadFromDisk();

        // Trigger an async collection shortly after startup + every 3 minutes
        this._startupId = GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, 2, () => {
            this._startupId = 0;
            this._runCollector(false);
            return GLib.SOURCE_REMOVE;
        });

        this._timeoutId = GLib.timeout_add_seconds(
            GLib.PRIORITY_DEFAULT,
            REFRESH_INTERVAL_SEC,
            () => {
                this._runCollector(false);
                return GLib.SOURCE_CONTINUE;
            }
        );
    }

    _setupFileMonitor() {
        try {
            const cacheDir = Gio.File.new_for_path(GLib.path_get_dirname(USAGE_FILE_PATH));
            if (!cacheDir.query_exists(null))
                cacheDir.make_directory_with_parents(null);

            const file = Gio.File.new_for_path(USAGE_FILE_PATH);
            this._fileMonitor = file.monitor_file(Gio.FileMonitorFlags.NONE, null);
            this._monitorChangedId = this._fileMonitor.connect('changed', (_m, _f, _o, eventType) => {
                if (
                    eventType === Gio.FileMonitorEvent.CHANGES_DONE_HINT ||
                    eventType === Gio.FileMonitorEvent.CREATED ||
                    eventType === Gio.FileMonitorEvent.MOVED_IN
                ) {
                    this._loadFromDisk();
                }
            });
        } catch (e) {
            console.error('Inferna AI Telemetry: failed to watch usage.json', e);
        }
    }

    _runCollector(force) {
        if (this._collecting)
            return;
        this._collecting = true;
        this._updateRefreshButtonState();

        try {
            const argv = force ? ['inferna-ai-usage', '--force'] : ['inferna-ai-usage'];
            const proc = Gio.Subprocess.new(argv, Gio.SubprocessFlags.NONE);
            proc.wait_async(null, (p, res) => {
                try {
                    p.wait_finish(res);
                } catch (_e) {
                    // ignore non-fatal collector failure
                }
                this._collecting = false;
                if (!this._destroyed)
                    this._loadFromDisk();
            });
        } catch (e) {
            this._collecting = false;
            console.error('Inferna AI Telemetry: failed to launch inferna-ai-usage', e);
            this._updateRefreshButtonState();
        }
    }

    _launchCommand(cmd) {
        if (!cmd)
            return;
        try {
            this.menu.close();
            const [ok, argv] = GLib.shell_parse_argv(cmd);
            if (ok && argv.length > 0)
                Gio.Subprocess.new(argv, Gio.SubprocessFlags.NONE);
        } catch (e) {
            console.error(`Inferna AI Telemetry: failed to launch '${cmd}'`, e);
        }
    }

    _loadFromDisk() {
        try {
            const file = Gio.File.new_for_path(USAGE_FILE_PATH);
            if (!file.query_exists(null)) {
                this._render();
                return;
            }
            const [ok, bytes] = file.load_contents(null);
            if (!ok)
                return;
            const text = new TextDecoder('utf-8').decode(bytes);
            this._snapshot = JSON.parse(text);
        } catch (_e) {
            // Keep previous snapshot on partial read
        }
        this._render();
    }

    _updateRefreshButtonState() {
        if (this._refreshBtn)
            this._refreshBtn.label = this._collecting ? '...' : '↻ Atualizar';
    }

    _render() {
        const snap = this._snapshot;

        // 1) Update Top Bar pill
        for (const cls of ['inferna-ai-level-ok', 'inferna-ai-level-warn', 'inferna-ai-level-hot']) {
            this._barIcon.remove_style_class_name(cls);
            this._barLabel.remove_style_class_name(cls);
        }

        if (snap && typeof snap.maxPercent === 'number' && snap.maxPercent >= 0) {
            const lvl = `inferna-ai-level-${levelSuffix(snap.maxPercent)}`;
            this._barIcon.add_style_class_name(lvl);
            this._barLabel.add_style_class_name(lvl);
            this._barLabel.text = `${snap.maxPercent}%`;
        } else {
            this._barIcon.add_style_class_name('inferna-ai-level-ok');
            this._barLabel.text = 'AI';
        }

        // 2) Rebuild Popup Cards
        this._popupBox.destroy_all_children();
        this._refreshBtn = null;

        // Header
        const header = new St.BoxLayout({
            style_class: 'inferna-ai-header',
            x_expand: true,
            y_align: Clutter.ActorAlign.CENTER,
        });

        const titleCol = new St.BoxLayout({
            ...VERTICAL_BOX,
            x_expand: true,
        });
        titleCol.add_child(new St.Label({
            text: 'Inferna AI Telemetry',
            style_class: 'inferna-ai-title',
        }));

        let metaText = 'Carregando telemetria...';
        if (snap) {
            const today = snap.summary?.sessionsToday ?? 0;
            const week = snap.summary?.sessionsWeek ?? 0;
            metaText = `Hoje: ${today} sess. · 7d: ${week} sess. · ${snap.updatedAtLocal || ''}`;
        }
        titleCol.add_child(new St.Label({
            text: metaText,
            style_class: 'inferna-ai-meta',
        }));

        this._refreshBtn = new St.Button({
            label: this._collecting ? '...' : '↻ Atualizar',
            style_class: 'inferna-ai-refresh-btn',
            can_focus: true,
            y_align: Clutter.ActorAlign.CENTER,
        });
        this._refreshBtn.connect('clicked', () => this._runCollector(true));

        header.add_child(titleCol);
        header.add_child(this._refreshBtn);
        this._popupBox.add_child(header);

        const agents = snap?.agents ?? [];
        if (agents.length === 0) {
            this._popupBox.add_child(new St.Label({
                text: 'Nenhum dado coletado ainda. Clique em Atualizar.',
                style_class: 'inferna-ai-note',
            }));
            return;
        }

        for (const ag of agents) {
            const card = new St.BoxLayout({
                ...VERTICAL_BOX,
                style_class: 'inferna-ai-card',
                x_expand: true,
            });

            // Card header: Agent Name + Plan Badge + Quick Launch >_
            const cardHead = new St.BoxLayout({
                style_class: 'inferna-ai-card-header',
                x_expand: true,
                y_align: Clutter.ActorAlign.CENTER,
            });
            cardHead.add_child(new St.Label({
                text: ag.name || ag.id,
                style_class: 'inferna-ai-agent-name',
                x_expand: true,
                y_align: Clutter.ActorAlign.CENTER,
            }));

            if (ag.plan) {
                const badgeCls = ag.status === 'idle'
                    ? 'inferna-ai-badge inferna-ai-badge-idle'
                    : 'inferna-ai-badge';
                cardHead.add_child(new St.Label({
                    text: ag.plan,
                    style_class: badgeCls,
                    y_align: Clutter.ActorAlign.CENTER,
                }));
            }

            if (ag.launchCmd) {
                const launchBtn = new St.Button({
                    label: '>_',
                    style_class: 'inferna-ai-launch-btn',
                    can_focus: true,
                    y_align: Clutter.ActorAlign.CENTER,
                });
                const cmd = ag.launchCmd;
                launchBtn.connect('clicked', () => this._launchCommand(cmd));
                cardHead.add_child(launchBtn);
            }
            card.add_child(cardHead);

            // Quota / limit meters
            const limits = ag.limits ?? [];
            for (const lim of limits) {
                const pct = Math.max(0, Math.min(100, Number(lim.percent ?? 0)));
                const suffix = levelSuffix(pct);

                const row = new St.BoxLayout({
                    ...VERTICAL_BOX,
                    style_class: 'inferna-ai-limit-row',
                    x_expand: true,
                });

                const top = new St.BoxLayout({
                    style_class: 'inferna-ai-limit-top',
                    x_expand: true,
                });
                top.add_child(new St.Label({
                    text: lim.label || 'Limite',
                    style_class: 'inferna-ai-limit-label',
                    x_expand: true,
                }));
                if (lim.resetsIn) {
                    top.add_child(new St.Label({
                        text: `↻ ${lim.resetsIn}`,
                        style_class: 'inferna-ai-limit-reset',
                    }));
                }
                top.add_child(new St.Label({
                    text: `${pct}%`,
                    style_class: `inferna-ai-limit-pct inferna-ai-level-${suffix}`,
                }));

                const track = new St.Widget({
                    style_class: 'inferna-ai-bar-track',
                    width: BAR_TRACK_WIDTH,
                    layout_manager: new Clutter.BinLayout(),
                });
                const fillW = pct > 0 ? Math.max(6, Math.round((BAR_TRACK_WIDTH * pct) / 100)) : 0;
                if (fillW > 0) {
                    const fill = new St.Widget({
                        style_class: `inferna-ai-bar-fill-${suffix}`,
                        width: fillW,
                        x_align: Clutter.ActorAlign.START,
                        y_align: Clutter.ActorAlign.CENTER,
                    });
                    track.add_child(fill);
                }

                row.add_child(top);
                row.add_child(track);
                card.add_child(row);
            }

            // Local activity / status note
            const noteParts = [];
            if (ag.local && typeof ag.local.sessionsToday === 'number' && limits.length > 0)
                noteParts.push(`Hoje: ${ag.local.sessionsToday} · 7d: ${ag.local.sessionsWeek}`);
            if (ag.note)
                noteParts.push(ag.note);

            if (noteParts.length > 0) {
                const noteLbl = new St.Label({
                    text: noteParts.join(' · '),
                    style_class: 'inferna-ai-note',
                });
                noteLbl.clutter_text.line_wrap = true;
                card.add_child(noteLbl);
            }

            this._popupBox.add_child(card);
        }
    }

    destroy() {
        this._destroyed = true;
        if (this._startupId) {
            GLib.Source.remove(this._startupId);
            this._startupId = 0;
        }
        if (this._timeoutId) {
            GLib.Source.remove(this._timeoutId);
            this._timeoutId = 0;
        }
        if (this._fileMonitor) {
            if (this._monitorChangedId) {
                this._fileMonitor.disconnect(this._monitorChangedId);
                this._monitorChangedId = 0;
            }
            this._fileMonitor.cancel();
            this._fileMonitor = null;
        }
        super.destroy();
    }
});

export default class InfernaAiTelemetryExtension extends Extension {
    enable() {
        this._indicator = new InfernaAiIndicator(this.path);
        Main.panel.addToStatusArea(this.uuid, this._indicator, 1, 'right');
    }

    disable() {
        if (this._indicator) {
            this._indicator.destroy();
            this._indicator = null;
        }
    }
}
