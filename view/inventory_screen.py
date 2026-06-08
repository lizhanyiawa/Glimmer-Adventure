from textual.screen import Screen
from textual.widgets import Static, Button
from textual.containers import Horizontal, Vertical, ScrollableContainer


class InventoryScreen(Screen):
    BINDINGS = [
        ("escape", "close", "关闭"),
        ("up", "prev_item", "上一个"),
        ("down", "next_item", "下一个"),
    ]

    CSS = """
    InventoryScreen {
        align: center middle;
        background: rgba(0, 0, 0, 0.75);
    }
    #inv_box {
        width: 72;
        height: auto;
        max-height: 36;
        border: thick #66fcf1;
        background: #161923;
        padding: 1 2;
    }
    .inv_title {
        text-align: center;
        text-style: bold;
        color: #66fcf1;
        margin-bottom: 1;
        height: auto;
    }
    #inv_main {
        height: 24;
    }
    #item_list {
        width: 30;
        height: 100%;
        border: solid #333333;
        background: #0f1016;
        overflow-y: auto;
    }
    #item_detail {
        width: 40;
        height: 100%;
        border: solid #333333;
        background: #0f1016;
        margin-left: 1;
        padding: 1 2;
        color: #c5c6c7;
    }
    .item_btn {
        width: 100%;
        background: #0f1016;
        color: #b2b2b2;
        border: none;
        text-align: left;
        padding-left: 1;
    }
    .item_btn:hover {
        background: #1f2833;
        color: #66fcf1;
        text-style: bold;
    }
    .item_btn_selected {
        background: #1f2833;
        color: #66fcf1;
        text-style: bold;
        border-left: solid #66fcf1;
    }
    .detail_name {
        color: #66fcf1;
        text-style: bold;
        margin-bottom: 1;
    }
    #detail_action_box {
        margin-top: 1;
        height: auto;
    }
    .action_btn {
        width: 100%;
        margin-bottom: 1;
        border: none;
        background: #11141e;
        color: #66fcf1;
    }
    .action_btn:hover {
        background: #66fcf1;
        color: #0b0c10;
        text-style: bold;
    }
    #btn_discard {
        background: #1a0505;
        color: #ff5555;
    }
    #btn_discard:hover {
        background: #ff5555;
        color: white;
    }
    #btn_discard:disabled {
        background: #111111;
        color: #333333;
    }
    .detail_type {
        color: #ffaa00;
        margin-bottom: 1;
    }
    .detail_body {
        color: #b2b2b2;
        margin-top: 1;
    }
    #inv_footer {
        height: auto;
        margin-top: 1;
    }
    #close_inv_btn {
        width: 100%;
        background: #ffaa00;
        color: #0b0c10;
        text-style: bold;
        border: none;
    }
    #close_inv_btn:hover {
        background: #ff007f;
        color: white;
        text-style: bold;
    }
    """

    def __init__(self):
        super().__init__()
        self._items = []
        self._selected = 0

    def compose(self):
        inv_mgr = self.app.engine.inv_mgr
        self._items = inv_mgr.all()

        with Vertical(id="inv_box"):
            yield Static("物品栏", classes="inv_title")

            with Horizontal(id="inv_main"):
                yield ScrollableContainer(id="item_list")
                with Vertical(id="item_detail_box"):
                    yield Static("", id="item_detail")
                    with Vertical(id="detail_action_box"):
                        yield Button("使用", id="btn_use", classes="action_btn")
                        yield Button("丢弃", id="btn_discard", classes="action_btn")

            with Vertical(id="inv_footer"):
                yield Static("↑↓ 选择物品  ·  [ 关闭 ] 点击下方按钮或按 ESC", classes="inv_title")
                yield Static(f"💰 铜币: {self.app.engine.state.stats.get('coins', 0)}", classes="inv_title")
                yield Button("[ 关闭 ]", id="close_inv_btn")

    def on_mount(self):
        self._build_item_list()
        if self._items:
            self._select(0)

    def _build_item_list(self):
        container = self.query_one("#item_list", ScrollableContainer)
        container.remove_children()

        for i, item in enumerate(self._items):
            if not isinstance(item, dict):
                continue
            qty = item.get("qty", 1)
            qty_str = f" x{qty}"
            label = f"{item['name']}{qty_str}"
            btn = Button(label, id=f"item_{i}")
            btn.can_focus = True
            container.mount(btn)

    def _select(self, index: int):
        if 0 <= index < len(self._items):
            self._selected = index
            self._highlight_selected()
            self._show_detail(self._items[index])

    def _highlight_selected(self):
        container = self.query_one("#item_list", ScrollableContainer)
        for i, child in enumerate(container.children):
            if not hasattr(child, "set_class"):
                continue
            if i == self._selected:
                child.set_class(True, "item_btn_selected")
            else:
                child.set_class(False, "item_btn_selected")

    def _show_detail(self, item: dict):
        inv_mgr = self.app.engine.inv_mgr
        type_name = inv_mgr.type_name(item.get("type", "misc"))
        qty = item.get("qty", 1)

        lines = [
            f"[b #66fcf1]{item.get('name', '???')}[/]",
            f"[#ffaa00]类型: {type_name}[/]",
            f"[#ffaa00]数量: {qty}[/]",
            "",
            f"[#b2b2b2]{item.get('desc', '(无描述)')}[/]",
        ]

        detail = self.query_one("#item_detail", Static)
        detail.update("\n".join(lines))

        # 刷新操作按钮状态
        btn_discard = self.query_one("#btn_discard", Button)
        # 带有 quest 标签或 type 为 key 的物品不能丢弃
        is_quest = item.get("type") == "quest" or item.get("type") == "key" or item.get("is_important", False)
        btn_discard.disabled = is_quest
        if is_quest:
            btn_discard.label = "丢弃 (重要物品)"
        else:
            btn_discard.label = "丢弃"

    def on_button_pressed(self, event: Button.Pressed):
        btn_id = event.button.id
        if btn_id == "close_inv_btn":
            self.action_close()
        elif btn_id == "btn_discard":
            self.action_discard()
        elif btn_id.startswith("item_"):
            index = int(btn_id.split("_")[1])
            self._select(index)

    def action_discard(self):
        if not self._items or self._selected >= len(self._items):
            return
        
        item = self._items[self._selected]
        inv_mgr = self.app.engine.inv_mgr
        
        if inv_mgr.remove(item["id"], 1):
            self.notify(f"已丢弃 {item['name']}")
            # 重新加载列表
            self._items = inv_mgr.all()
            self._build_item_list()
            
            if not self._items:
                self.query_one("#item_detail", Static).update("")
                self.query_one("#btn_discard", Button).disabled = True
            else:
                self._selected = min(self._selected, len(self._items) - 1)
                self._select(self._selected)

    def on_click(self, event):
        if event.control is self:
            self.action_close()

    def action_prev_item(self):
        if self._items:
            self._select((self._selected - 1) % len(self._items))

    def action_next_item(self):
        if self._items:
            self._select((self._selected + 1) % len(self._items))

    def action_close(self):
        self.app.pop_screen()