import GLib from 'gi://GLib';
import Gio from 'gi://Gio';
import GObject from 'gi://GObject';
import St from 'gi://St';
import Clutter from 'gi://Clutter';
import Pango from 'gi://Pango';

import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as PanelMenu from 'resource:///org/gnome/shell/ui/panelMenu.js';
import * as PopupMenu from 'resource:///org/gnome/shell/ui/popupMenu.js';

const TODO = GLib.build_filenamev([GLib.get_home_dir(), '.local', 'bin', 'todo']);
const DATA_DIR = GLib.build_filenamev([GLib.get_user_data_dir(), 'todo']);
const REFRESH_SECONDS = 30;

function todo(args) {
    return new Promise((resolve, reject) => {
        try {
            const proc = Gio.Subprocess.new(
                [TODO, ...args],
                Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_PIPE);
            proc.communicate_utf8_async(null, null, (p, res) => {
                try {
                    const [, out, err] = p.communicate_utf8_finish(res);
                    if (p.get_successful())
                        resolve(out);
                    else
                        reject(new Error(err.trim()));
                } catch (e) {
                    reject(e);
                }
            });
        } catch (e) {
            reject(e);
        }
    });
}

function hm(date) {
    return `${String(date.getHours()).padStart(2, '0')}:${String(date.getMinutes()).padStart(2, '0')}`;
}

/** End of an item as HH:MM; items without one are taken to last 30 minutes. */
function endOf(item) {
    if (item.end_time)
        return item.end_time;
    const [h, m] = item.time.split(':').map(Number);
    const end = new Date(2000, 0, 1, h, m + 30);
    return end.getDate() === 1 ? hm(end) : '23:59';
}

function clock(seconds) {
    const s = Math.max(0, seconds);
    return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`;
}

const Indicator = GObject.registerClass(
class Indicator extends PanelMenu.Button {
    _init() {
        super._init(0.5, 'Todo');
        this._label = new St.Label({text: '✓', y_align: Clutter.ActorAlign.CENTER});
        this.add_child(this._label);
        this._snapshot = null;
        this._raw = '';
        this._ticks = 0;
        // "date id time" of items already announced, so each start rings once.
        this._announced = new Set();
        this._minute = hm(new Date());

        // The CLI, the desktop app and sync all write the same database, so
        // watching its folder picks up changes from any of them.
        this._monitor = Gio.File.new_for_path(DATA_DIR)
            .monitor_directory(Gio.FileMonitorFlags.NONE, null);
        this._monitor.connect('changed', () => this._refreshSoon());

        this._tickId = GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, 1, () => {
            if (++this._ticks % REFRESH_SECONDS === 0)
                this._refresh();
            this._announceStarts();
            this._updateLabel();
            return GLib.SOURCE_CONTINUE;
        });
        this.menu.connect('open-state-changed', (_menu, open) => {
            if (open)
                this._refresh();
        });
        this._refresh();
    }

    _refreshSoon() {
        if (this._soonId)
            return;
        this._soonId = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 300, () => {
            this._soonId = 0;
            this._refresh();
            return GLib.SOURCE_REMOVE;
        });
    }

    async _refresh() {
        try {
            const raw = await todo(['--json', 'today']);
            if (raw === this._raw)
                return;
            this._raw = raw;
            this._snapshot = JSON.parse(raw);
            this._error = null;
        } catch (e) {
            this._snapshot = null;
            this._raw = '';
            this._error = e.message;
        }
        this._updateLabel();
        this._buildMenu();
    }

    async _run(args) {
        try {
            await todo(args);
        } catch (e) {
            Main.notifyError('Todo', e.message);
        }
        this._refresh();
    }

    _focusSecondsLeft() {
        const focus = this._snapshot?.focus;
        if (!focus)
            return null;
        return Math.round((Date.parse(focus.ends_at) - Date.now()) / 1000);
    }

    /** Rings and notifies when a task or timed habit reaches its start time. */
    _announceStarts() {
        const now = hm(new Date());
        if (now === this._minute)
            return;
        this._minute = now;
        const snap = this._snapshot;
        if (!snap)
            return;
        for (const i of snap.items) {
            const key = `${snap.date} ${i.id} ${i.time}`;
            if (i.done || i.time !== now || this._announced.has(key))
                continue;
            this._announced.add(key);
            const until = i.kind === 'task' && i.end_time ? `Until ${i.end_time}` : (i.kind === 'habit' ? 'Habit' : 'Now');
            Main.notify(i.title, until);
            global.display.get_sound_player().play_from_theme('alarm-clock-elapsed', i.title, null);
        }
    }

    /** The unticked task whose time slot covers now, if any. */
    _currentTask() {
        const now = hm(new Date());
        return this._snapshot?.items.find(i =>
            i.kind === 'task' && !i.done && i.time && i.time <= now && now < endOf(i)) ?? null;
    }

    _updateLabel() {
        const snap = this._snapshot;
        this._label.remove_style_class_name('todo-current');
        if (!snap) {
            this._label.text = '✓ –';
            return;
        }
        const left = this._focusSecondsLeft();
        if (left !== null) {
            if (left <= 0) {
                const focus = snap.focus;
                snap.focus = null;
                Main.notify(
                    focus.kind === 'break' ? 'Break over' : 'Focus session finished',
                    focus.task ?? `${focus.planned_min} minutes`);
                this._refresh();
            } else {
                this._label.text = `${snap.focus.kind === 'break' ? '☕' : '⏱'} ${clock(left)}`;
                return;
            }
        }
        const current = this._currentTask();
        if (current) {
            const title = current.title.length > 42 ? `${current.title.slice(0, 41)}…` : current.title;
            this._label.text = `${title}  ·  till ${endOf(current)}`;
            this._label.add_style_class_name('todo-current');
            return;
        }
        this._label.text = `✓ ${snap.items.filter(i => i.done).length}/${snap.items.length}`;
    }

    _checkItem(text, done, onActivate) {
        const item = new PopupMenu.PopupMenuItem(text);
        item.add_style_class_name('todo-item');
        if (done)
            item.add_style_class_name('todo-done');
        item.label.clutter_text.ellipsize = Pango.EllipsizeMode.END;
        item.setOrnament(done ? PopupMenu.Ornament.CHECK : PopupMenu.Ornament.NONE);
        item.connect('activate', onActivate);
        return item;
    }

    _action(text, args) {
        const item = new PopupMenu.PopupMenuItem(text);
        item.connect('activate', () => this._run(args));
        return item;
    }

    _buildMenu() {
        this.menu.removeAll();
        const snap = this._snapshot;
        if (!snap) {
            const item = new PopupMenu.PopupMenuItem(this._error ?? 'Loading…', {reactive: false});
            this.menu.addMenuItem(item);
            return;
        }

        if (snap.items.length === 0) {
            this.menu.addMenuItem(new PopupMenu.PopupMenuItem('Nothing scheduled today', {reactive: false}));
        }
        // Tasks and habits together, in time order.
        for (const i of snap.items) {
            const time = i.time ? `${i.time}  ` : '';
            const toggle = i.kind === 'habit'
                ? ['habit', i.done ? 'uncheck' : 'check', i.id]
                : [i.done ? 'undo' : 'done', i.id];
            this.menu.addMenuItem(this._checkItem(`${time}${i.title}`, i.done, () => this._run(toggle)));
        }
        if (snap.overdue > 0) {
            this.menu.addMenuItem(new PopupMenu.PopupMenuItem(
                `${snap.overdue} overdue from earlier days`, {reactive: false}));
        }

        this.menu.addMenuItem(new PopupMenu.PopupSeparatorMenuItem());
        if (snap.focus) {
            const what = snap.focus.task ? `: ${snap.focus.task}` : '';
            this.menu.addMenuItem(this._action(
                `Stop ${snap.focus.kind === 'break' ? 'break' : 'focus'}${what}`, ['focus', 'stop']));
        } else {
            const focus = new PopupMenu.PopupSubMenuMenuItem(
                `Start focus  (${snap.focused_min} min today)`);
            focus.menu.addMenuItem(this._action('25 minutes, no task', ['focus', 'start']));
            for (const t of snap.tasks.filter(t => !t.done)) {
                const item = this._action(`25 min: ${t.title}`, ['focus', 'start', t.id]);
                item.add_style_class_name('todo-item');
                item.label.clutter_text.ellipsize = Pango.EllipsizeMode.END;
                focus.menu.addMenuItem(item);
            }
            focus.menu.addMenuItem(this._action('5 minute break', ['focus', 'start', '--break']));
            this.menu.addMenuItem(focus);
        }
    }

    destroy() {
        if (this._tickId)
            GLib.source_remove(this._tickId);
        if (this._soonId)
            GLib.source_remove(this._soonId);
        this._tickId = this._soonId = 0;
        this._monitor?.cancel();
        this._monitor = null;
        super.destroy();
    }
});

export default class TodoExtension extends Extension {
    enable() {
        this._indicator = new Indicator();
        Main.panel.addToStatusArea(this.uuid, this._indicator);
    }

    disable() {
        this._indicator?.destroy();
        this._indicator = null;
    }
}
