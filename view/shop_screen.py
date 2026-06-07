"""商店界面"""

from textual.screen import Screen
from textual.widgets import Static, Button
from textual.containers import Horizontal, Vertical, ScrollableContainer
from textual import on


class ShopScreen(Screen):
    """商店交易界面。

    shop_id: 商店 ID（对应 shops.json 中的 key）。
    从 app.engine.get_shop(shop_id) 获取数据。
    """

    BINDINGS = [
        ("escape", "close", "关闭"),
        ("up", "prev_item", "上一个"),
        ("down", "next_item", "下一个"),
        ("enter", "buy_selected", "购买"),
    ]

    CSS = """
    ShopScreen {
        align: center middle;
        background: rgba(0, 0, 0, 0.75);
    }
    #shop_box {
        width: 76;
        height: 36;
        border: thick #ffaa00;
        background: #161923;
        padding: 1 2;
    }
    #shop_header {
        height: 3;
        margin-bottom: 1;
    }
    #shop_title {
        text-align: center;
        text-style: bold;
        color: #ffaa00;
        width: 100%;
    }
    #shop_coins {
        text-align: right;
        color: #ffdd00;
        width: 100%;
        text-style: bold;
    }
    #shop_main {
        height: 26;
    }
    #shop_list {
        width: 32;
        height: 100%;
        border: solid #333333;
        background: #0f1016;
        overflow-y: auto;
    }
    #shop_detail {
        width: 40;
        height: 100%;
        border: solid #333333;
        background: #0f1016;
        margin-left: 1;
        padding: 1 2;
        color: #c5c6c7;
    }
    .shop_item_btn {
        width: 100%;
        background: #0f1016;
        color: #b2b2b2;
        border: none;
        text-align: left;
        padding-left: 1;
    }
    .shop_item_btn:hover {
        background: #1f2833;
        color: #ffaa00;
        text-style: bold;
    }
    .shop_item_selected {
        background: #1f2833;
        color: #ffaa00;
        text-style: bold;
        border-left: solid #ffaa00;
    }
    .detail_name {
        color: #ffaa00;
        text-style: bold;
        margin-bottom: 1;
    }
    .detail_price {
        color: #ffdd00;
        margin-bottom: 1;
    }
    .detail_stock {
        color: #888888;
        margin-bottom: 1;
    }
    #shop_bottom {
        height: 3;
        margin-top: 1;
    }
    #shop_greeting {
        color: #888888;
        text-style: italic;
        width: 75%;
    }
    #btn_buy {
        width: 25%;
        border: solid #ffaa00;
        background: #11141e;
        color: #ffaa00;
        text-style: bold;
        content-align: center middle;
    }
    #btn_buy:hover {
        background: #ffaa00;
        color: #0b0c10;
    }
    #btn_buy:disabled {
        background: #111111;
        color: #444444;
        border: solid #444444;
    }
    """

    def __init__(self, shop_id: str):
        super().__init__()
        self._shop_id = shop_id
        self._items = []
        self._selected = 0

    def compose(self):
        with Vertical(id="shop_box"):
            with Vertical(id="shop_header"):
                yield Static("商店加载中…", id="shop_title")
                yield Static("", id="shop_coins")

            with Horizontal(id="shop_main"):
                yield ScrollableContainer(id="shop_list")
                yield Static("", id="shop_detail")

            with Horizontal(id="shop_bottom"):
                yield Static("", id="shop_greeting")
                yield Button("[ Enter ] 购买", id="btn_buy")

    def on_mount(self):
        engine = self.app.engine
        shop = engine.get_shop(self._shop_id)
        if not shop:
            self.query_one("#shop_title", Static).update("[错误] 商店数据不存在")
            return

        self._shop_data = shop
        self._items = shop.get("items", [])

        self.query_one("#shop_title", Static).update(f"── {shop.get('name', '???')} ──")
        self.query_one("#shop_coins", Static).update(
            f"💰 {engine.state.stats.get('coins', 0)} 铜币"
        )
        self.query_one("#shop_greeting", Static).update(shop.get("greeting", ""))

        self._rebuild_list()
        if self._items:
            self._select(0)

    def _rebuild_list(self):
        container = self.query_one("#shop_list", ScrollableContainer)
        container.remove_children()

        for i, item in enumerate(self._items):
            stock_str = ""
            stock = item.get("stock", -1)
            if stock >= 0:
                stock_str = f"  [库存:{stock}]"
            btn = Button(
                f"{item['name']}  {item['price']}铜{stock_str}",
                id=f"shop_item_{i}",
                classes="shop_item_btn",
            )
            container.mount(btn)

    def _select(self, index: int):
        self._selected = max(0, min(index, len(self._items) - 1))
        for i, child in enumerate(self.query("#shop_list").nodes):
            if hasattr(child, "set_class"):
                child.set_class(i == self._selected, "shop_item_selected")
        self._show_detail()

    def _show_detail(self):
        if not self._items:
            return
        item = self._items[self._selected]
        stock = item.get("stock", -1)
        stock_text = f"库存: {stock} 个" if stock >= 0 else "无限供应"

        lines = [
            f"[detail_name]{item['name']}[/detail_name]",
            f"[detail_price]价格: {item['price']} 铜币[/detail_price]",
            f"[detail_stock]{stock_text}[/detail_stock]",
            "",
            item.get("desc", "(无描述)"),
        ]
        self.query_one("#shop_detail", Static).update("\n".join(lines))

        engine = self.app.engine
        coins = engine.state.stats.get("coins", 0)
        can_buy = coins >= item["price"] and (stock < 0 or stock > 0)
        self.query_one("#btn_buy", Button).disabled = not can_buy

    def action_prev_item(self):
        if self._items and self._selected > 0:
            self._select(self._selected - 1)

    def action_next_item(self):
        if self._items and self._selected < len(self._items) - 1:
            self._select(self._selected + 1)

    def action_buy_selected(self):
        if not self._items:
            return
        item = self._items[self._selected]
        self._do_buy(item)

    @on(Button.Pressed, "#btn_buy")
    def on_buy_click(self):
        if not self._items:
            return
        self._do_buy(self._items[self._selected])

    def _do_buy(self, item):
        engine = self.app.engine
        result = engine.buy_item(self._shop_id, item["item_id"], 1)

        if result["success"]:
            self.notify(result["message"], title="购买成功")
            # refresh coins display
            self.query_one("#shop_coins", Static).update(
                f"💰 {engine.state.stats.get('coins', 0)} 铜币"
            )
            # reload shop data to get updated stock
            self._shop_data = engine.get_shop(self._shop_id)
            self._items = self._shop_data.get("items", [])
            old_selected = self._selected
            self._rebuild_list()
            if self._items:
                self._select(min(old_selected, len(self._items) - 1))
            else:
                self._selected = 0
                self.query_one("#shop_detail", Static).update("商品已售罄")
                self.query_one("#btn_buy", Button).disabled = True
        else:
            self.notify(result["message"], title="无法购买", severity="warning")

    def action_close(self):
        self.app.pop_screen()

    @on(Button.Pressed, ".shop_item_btn")
    def on_item_click(self, event: Button.Pressed):
        idx = int(event.button.id.split("_")[-1])
        self._select(idx)
