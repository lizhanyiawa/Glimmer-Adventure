import datetime
from textual.screen import Screen
from textual.widgets import Static, Button, Input
from textual.containers import Horizontal, Vertical, ScrollableContainer


class DiaryScreen(Screen):
    BINDINGS = [
        ("escape", "close", "关闭"),
        ("up", "prev_item", "上一个"),
        ("down", "next_item", "下一个"),
        ("n", "new_note", "新建笔记"),
        ("d", "delete_note", "删除笔记"),
        ("t", "track", "追踪任务"),
    ]

    CSS = """
    DiaryScreen {
        align: center middle;
        background: rgba(0, 0, 0, 0.75);
    }
    #diary_box {
        width: 66;
        height: 34;
        border: thick #e6b800;
        background: #161923;
        padding: 1 2;
    }
    .diary_title {
        text-align: center;
        text-style: bold;
        color: #e6b800;
        margin-bottom: 1;
        height: 1;
    }
    #diary_main {
        height: 24;
    }
    #entry_list {
        width: 26;
        height: 100%;
        border: solid #444444;
        background: #0f1016;
        overflow-y: auto;
    }
    .section_header {
        color: #e6b800;
        text-style: bold;
        background: #1a1a24;
        padding-left: 1;
        height: 1;
    }
    .task_btn {
        width: 100%;
        background: #0f1016;
        color: #66fcf1;
        border: none;
        text-align: left;
        padding-left: 1;
    }
    .task_btn:hover {
        background: #1f2833;
        color: #66fcf1;
        text-style: bold;
    }
    .task_btn_done {
        width: 100%;
        background: #0f1016;
        color: #557766;
        border: none;
        text-align: left;
        padding-left: 1;
        text-style: strike;
    }
    .note_btn {
        width: 100%;
        background: #0f1016;
        color: #ffaa00;
        border: none;
        text-align: left;
        padding-left: 1;
    }
    .note_btn:hover {
        background: #1f2833;
        color: #ffaa00;
        text-style: bold;
    }
    .entry_unread {
        border-left: solid #ffe066;
    }
    .entry_selected {
        border-left: solid #e6b800;
        background: #1f2833;
    }
    #entry_detail {
        width: 36;
        height: 100%;
        border: solid #444444;
        background: #0f1016;
        margin-left: 1;
        padding: 1 2;
        color: #c5c6c7;
        overflow-y: auto;
    }
    #diary_footer {
        height: 4;
        margin-top: 1;
    }
    #diary_footer Static {
        color: #888888;
        text-align: center;
        width: 100%;
    }
    #tracked_task_btn {
        width: 100%;
        background: #1a1a10;
        color: #e6b800;
        border: solid #e6b800;
    }
    #tracked_task_btn:hover {
        background: #e6b800;
        color: #0b0c10;
        text-style: bold;
    }
    #new_note_btn {
        width: 100%;
        background: #e6b800;
        color: #0b0c10;
        text-style: bold;
        border: none;
    }
    #new_note_btn:hover {
        background: #ffcc00;
        text-style: bold;
    }
    #close_diary_btn {
        width: 100%;
        background: #ff007f;
        color: white;
        border: none;
    }
    #close_diary_btn:hover {
        background: #ffaa00;
        text-style: bold;
    }
    #delete_note_btn {
        width: 100%;
        background: #1a0505;
        color: #ff5555;
        border: none;
    }
    #delete_note_btn:hover {
        background: #ff5555;
        color: white;
        text-style: bold;
    }

    NoteInputScreen {
        align: center middle;
        background: rgba(0, 0, 0, 0.8);
    }
    #note_input_box {
        width: 52;
        border: solid #e6b800;
        background: #161923;
        padding: 1 2;
    }
    #note_title_input {
        width: 100%;
        margin-bottom: 1;
    }
    #note_content_input {
        width: 100%;
        height: 4;
        margin-bottom: 1;
    }
    #note_btn_row {
        width: 100%;
        height: 3;
        align: right middle;
    }
    #note_btn_row Button {
        margin-left: 1;
    }
    """

    def __init__(self):
        super().__init__()
        self._entries = []
        self._selected = 0

    def compose(self):
        with Vertical(id="diary_box"):
            yield Static("日 记", classes="diary_title")

            with Horizontal(id="diary_main"):
                yield ScrollableContainer(id="entry_list")
                yield Static("", id="entry_detail")

            with Vertical(id="diary_footer"):
                yield Static("[N] 新建笔记  [D] 删除笔记  [T] 追踪  ·  点击关闭按钮或按 ESC 返回", classes="diary_title")
                with Horizontal():
                    yield Button("[N] 新建笔记", id="new_note_btn")
                    yield Button("[T] 追踪任务", id="tracked_task_btn")
                    yield Button("[D] 删除笔记", id="delete_note_btn")
                    yield Button("[ 关闭 ]", id="close_diary_btn")

    def on_mount(self):
        self.query_one("#delete_note_btn").display = False
        self.query_one("#tracked_task_btn").display = False
        self._has_unread = self.app.engine.state.flags.get("diary_unread", False)
        self.app.engine.state.flags["diary_unread"] = False
        self._build_entry_list()
        if self._entries:
            self._select(0)

    def _build_entry_list(self):
        diary = self.app.engine.state.diary
        tasks = diary.get("tasks", [])
        notes = diary.get("notes", [])

        self._entries = []

        container = self.query_one("#entry_list", ScrollableContainer)
        for child in list(container.children):
            child.remove()

        widgets = []
        new_items = self._has_unread

        if tasks:
            widgets.append(Static("── 任务 ──", classes="section_header"))
            for i, t in enumerate(tasks):
                idx = len(self._entries)
                self._entries.append(("task", idx, t))
                done = t.get("done", False)
                label = t.get("title", "???")
                if done:
                    label = "✓ " + label
                btn = Button(label, id=f"entry_{idx}")
                btn.can_focus = True
                if done:
                    btn.set_class(True, "task_btn_done")
                else:
                    btn.set_class(True, "task_btn")
                    if new_items:
                        btn.set_class(True, "entry_unread")
                widgets.append(btn)

        if notes:
            widgets.append(Static("── 笔记 ──", classes="section_header"))
            for i, n in enumerate(notes):
                idx = len(self._entries)
                self._entries.append(("note", idx, n))
                label = n.get("title", "???")
                btn = Button(label, id=f"entry_{idx}")
                btn.can_focus = True
                btn.set_class(True, "note_btn")
                if new_items:
                    btn.set_class(True, "entry_unread")
                widgets.append(btn)

        if widgets:
            container.mount(*widgets)

    def _select(self, index: int):
        if 0 <= index < len(self._entries):
            self._selected = index
            self._highlight_selected()
            self._show_detail(self._entries[index])

    def _highlight_selected(self):
        container = self.query_one("#entry_list", ScrollableContainer)
        children = list(container.children)
        entry_start = 0
        for c in children:
            if isinstance(c, Static):
                entry_start += 1
                continue
            entry_idx = entry_start - (len([x for x in children[:entry_start] if isinstance(x, Static)]))
            if hasattr(c, "set_class"):
                real_idx = entry_idx
                if real_idx < len(self._entries) and real_idx == self._selected:
                    c.set_class(True, "entry_selected")
                else:
                    c.set_class(False, "entry_selected")
            entry_start += 1

    def _show_detail(self, entry):
        etype, _, data = entry
        if etype == "task":
            self.query_one("#delete_note_btn").display = False
            self.query_one("#tracked_task_btn").display = True
            tracked_id = self.app.engine.state.flags.get("tracked_task_id", "")
            task_id = data.get("id", "")
            if tracked_id == task_id:
                self.query_one("#tracked_task_btn").label = "[T] 取消追踪"
            else:
                self.query_one("#tracked_task_btn").label = "[T] 追踪任务"
            done = data.get("done", False)
            status = "[#557766]已完成[/]" if done else "[#66fcf1]进行中[/]"
            lines = [
                f"[b #e6b800]{data.get('title', '???')}[/]",
                f"状态: {status}",
                "",
                f"[#c5c6c7]{data.get('content', '(无描述)')}[/]",
            ]
        else:
            self.query_one("#delete_note_btn").display = True
            self.query_one("#tracked_task_btn").display = False
            created = data.get("created", "")
            lines = [
                f"[b #ffaa00]{data.get('title', '???')}[/]",
                f"[#888888]记录于: {created}[/]",
                "",
                f"[#c5c6c7]{data.get('content', '')}[/]",
            ]
        self.query_one("#entry_detail", Static).update("\n".join(lines))

    def on_button_pressed(self, event: Button.Pressed):
        btn_id = event.button.id
        if btn_id == "close_diary_btn":
            self.action_close()
        elif btn_id == "new_note_btn":
            self.action_new_note()
        elif btn_id == "delete_note_btn":
            self.action_delete_note()
        elif btn_id == "tracked_task_btn":
            self.action_track()
        elif btn_id.startswith("entry_"):
            index = int(btn_id.split("_")[1])
            self._select(index)

    def on_click(self, event):
        if event.control is self:
            self.action_close()

    def action_prev_item(self):
        if self._entries:
            self._select((self._selected - 1) % len(self._entries))

    def action_next_item(self):
        if self._entries:
            self._select((self._selected + 1) % len(self._entries))

    def action_new_note(self):
        self.app.push_screen(NoteInputScreen(self._on_note_saved))

    def action_delete_note(self):
        if not self._entries or self._selected >= len(self._entries):
            return
        entry = self._entries[self._selected]
        etype, _, data = entry
        if etype != "note":
            self.notify("只能删除笔记，不能删除任务", title="提示")
            return

        note_id = data.get("id", "")
        notes = self.app.engine.state.diary.get("notes", [])
        for i, n in enumerate(notes):
            if n.get("id") == note_id:
                notes.pop(i)
                break

        self._build_entry_list()
        if self._entries:
            self._selected = min(self._selected, len(self._entries) - 1)
            self._select(self._selected)
        else:
            self.query_one("#entry_detail", Static).update("")
            self.query_one("#delete_note_btn").display = False
            self.query_one("#tracked_task_btn").display = False
        self.notify("笔记已删除")

    def action_track(self):
        if not self._entries or self._selected >= len(self._entries):
            return
        entry = self._entries[self._selected]
        etype, _, data = entry
        if etype != "task":
            self.notify("只能追踪任务", title="提示")
            return

        task_id = data.get("id", "")
        current = self.app.engine.state.flags.get("tracked_task_id", "")

        if current == task_id:
            self.app.engine.state.flags["tracked_task_id"] = ""
            self.query_one("#tracked_task_btn").label = "[T] 追踪任务"
            self.notify("已取消追踪")
        else:
            self.app.engine.state.flags["tracked_task_id"] = task_id
            self.query_one("#tracked_task_btn").label = "[T] 取消追踪"
            self.notify(f"正在追踪: {data.get('title', '???')}")

        # 刷新主界面的追踪任务显示
        if self.app.screen_stack:
            main = None
            for s in reversed(self.app.screen_stack):
                if hasattr(s, "_refresh_tracked_task"):
                    main = s
                    break
            if main:
                main._refresh_tracked_task()

    def _on_note_saved(self, title: str, content: str):
        if not title.strip():
            return
        note = {
            "id": f"note_{datetime.datetime.now().strftime('%Y%m%d%H%M%S')}",
            "title": title.strip(),
            "content": content.strip(),
            "created": datetime.datetime.now().strftime("%Y-%m-%d %H:%M")
        }
        self.app.engine.state.diary["notes"].append(note)
        self.app.engine.state.flags["diary_unread"] = True
        self._build_entry_list()
        if self._entries:
            self._select(len(self._entries) - 1)
        self.notify("笔记已保存")

    def action_close(self):
        self.app.pop_screen()


class NoteInputScreen(Screen):
    BINDINGS = [
        ("escape", "cancel", "取消"),
    ]

    CSS = """
    NoteInputScreen {
        align: center middle;
        background: rgba(0, 0, 0, 0.8);
    }
    #note_input_box {
        width: 52;
        border: solid #e6b800;
        background: #161923;
        padding: 1 2;
    }
    #note_input_box Static {
        color: #e6b800;
        text-style: bold;
    }
    #note_title_input {
        width: 100%;
        margin-bottom: 1;
    }
    #note_content_input {
        width: 100%;
        height: 4;
        margin-bottom: 1;
    }
    #note_btn_row {
        width: 100%;
        height: auto;
        align: right middle;
    }
    #note_btn_row Button {
        margin-left: 1;
    }
    """

    def __init__(self, on_saved):
        super().__init__()
        self._on_saved = on_saved

    def compose(self):
        with Vertical(id="note_input_box"):
            yield Static("新建笔记")
            yield Static("标题:")
            yield Input(placeholder="输入笔记标题...", id="note_title_input")
            yield Static("内容:")
            yield Input(placeholder="输入笔记内容...", id="note_content_input")
            with Horizontal(id="note_btn_row"):
                yield Button("[ESC] 取消", id="cancel_note_btn")
                yield Button("[ 保存 ]", id="save_note_btn")

    def on_button_pressed(self, event: Button.Pressed):
        if event.button.id == "save_note_btn":
            title = self.query_one("#note_title_input", Input).value
            content = self.query_one("#note_content_input", Input).value
            self.app.pop_screen()
            self._on_saved(title, content)
        elif event.button.id == "cancel_note_btn":
            self.app.pop_screen()

    def on_click(self, event):
        if event.control is self:
            self.app.pop_screen()

    def action_cancel(self):
        self.app.pop_screen()