extends CanvasLayer
## 全局演出助手（autoload：Fx）。管三件事：
##   1. 场景切换的黑场淡入淡出——所有换场景都走 goto()，别再裸调 change_scene_to_file
##   2. 元素的入场动效（淡入 / 弹入 / 错峰淡入）
##   3. 往界面里塞一层"氛围粒子"（飘浮尘埃、火星），放在内容后面
##
## 注意：动效用的 Tween 都建在目标节点自己身上（node.create_tween），
## 这样场景一销毁 tween 就跟着没了，不会出现"目标已被释放"的报错。

const FADE_OUT := 0.20   ## 切走时的黑场时长
const FADE_IN := 0.30    ## 切来后的黑场时长
## "虚血"残影排空的时长。原先是 0.55，太快了、像是一闪而过，
## 调长到 1.4（约 2.5 倍）才看得出"慢慢排空"的过程。
const GHOST_DURATION := 1.4

var _overlay: ColorRect = null
var _busy: bool = false


func _ready() -> void:
	layer = 128  # 盖在所有界面之上
	_overlay = ColorRect.new()
	_overlay.color = Color.BLACK
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.modulate.a = 0.0
	add_child(_overlay)


## ────────────────────────── 场景切换 ──────────────────────────

## 黑场 → 换场景 → 亮起。取代裸的 get_tree().change_scene_to_file()
func goto(path: String) -> void:
	if _busy:
		return
	_busy = true
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP  # 黑场期间挡掉误点
	var out := create_tween()
	out.tween_property(_overlay, "modulate:a", 1.0, FADE_OUT)
	await out.finished

	get_tree().change_scene_to_file(path)
	await get_tree().process_frame
	await get_tree().process_frame  # 多等一帧，让新场景把界面搭好

	var back := create_tween()
	back.tween_property(_overlay, "modulate:a", 0.0, FADE_IN)
	await back.finished
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_busy = false


## ────────────────────────── 入场动效 ──────────────────────────

## 淡入。容器管的节点只能用这个（position/size 会被容器覆盖）。
func fade_in(node: Control, delay := 0.0, dur := 0.3) -> void:
	if node == null:
		return
	node.modulate.a = 0.0
	var tw := node.create_tween()
	if delay > 0.0:
		tw.tween_interval(delay)
	tw.tween_property(node, "modulate:a", 1.0, dur).set_trans(Tween.TRANS_SINE)


## 弹入：淡入 + 从 0.94 倍放大回来。适合弹窗面板这类"跳出来"的元素。
## 会先等一帧让容器算好尺寸，再把缩放中心挪到正中，免得从左上角放大。
func pop_in(node: Control, delay := 0.0, dur := 0.3) -> void:
	if node == null:
		return
	node.modulate.a = 0.0
	await get_tree().process_frame
	if not is_instance_valid(node):
		return
	node.pivot_offset = node.size * 0.5
	if not node.resized.is_connected(_sync_pivot.bind(node)):
		node.resized.connect(_sync_pivot.bind(node))
	node.scale = Vector2(0.94, 0.94)
	var tw := node.create_tween()
	tw.set_parallel(true)
	tw.tween_property(node, "modulate:a", 1.0, dur).set_delay(delay).set_trans(Tween.TRANS_SINE)
	tw.tween_property(node, "scale", Vector2.ONE, dur).set_delay(delay) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## 一组控件错峰淡入（列表、按钮排）
func stagger(nodes: Array, step := 0.04, dur := 0.26) -> void:
	var i := 0
	for n in nodes:
		if n is Control and is_instance_valid(n):
			fade_in(n, step * i, dur)
		i += 1


func _sync_pivot(node: Control) -> void:
	if is_instance_valid(node):
		node.pivot_offset = node.size * 0.5


# ────────────────────────── 血条"虚血" ──────────────────────────

## 血条掉血时的"虚血"残影：在 bar 上叠一块浅色区域，
## 从变化前的比例慢慢收缩到变化后的比例，血条就不会"啪"地一步到位。
##
## 实现要点：残影是 bar 的子节点，所以只覆盖 [new_ratio, prev_ratio] 这一段
## （也就是刚掉掉的那一截），不会盖住还活着的部分。
func ghost_drain(bar: Control, prev_ratio: float, new_ratio: float) -> void:
	if bar == null or not is_instance_valid(bar):
		return
	if prev_ratio <= new_ratio + 0.005:
		return   # 没掉血（或回血），不用画残影

	var ghost := ColorRect.new()
	ghost.color = Palette.BAR_GHOST
	ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ghost.anchor_left = new_ratio
	ghost.anchor_right = prev_ratio
	ghost.anchor_top = 0.0
	ghost.anchor_bottom = 1.0
	bar.add_child(ghost)

	var tw := ghost.create_tween()
	tw.set_parallel(true)
	tw.tween_property(ghost, "anchor_right", new_ratio, GHOST_DURATION) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(ghost, "modulate:a", 0.0, GHOST_DURATION)
	tw.finished.connect(ghost.queue_free)


# ────────────────────────── 提醒（粒子 + 轻微呼吸） ──────────────────────────

## 在 node 上撒一把发光小点，用完自己销毁
func sparkle(node: Control, color: Color, amount := 14) -> void:
	if node == null or not is_instance_valid(node):
		return
	var p := CPUParticles2D.new()
	p.amount = amount
	p.lifetime = 0.7
	p.one_shot = true
	p.explosiveness = 0.9
	p.local_coords = false
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = maxf(node.size.x, node.size.y) * 0.35
	p.position = node.size * 0.5
	p.direction = Vector2(0, -1)
	p.spread = 180.0
	p.gravity = Vector2(0, 40)
	p.initial_velocity_min = 25.0
	p.initial_velocity_max = 70.0
	p.scale_amount_min = 1.0
	p.scale_amount_max = 2.6
	p.color = color
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.add_child(p)
	p.emitting = true

	await get_tree().create_timer(1.0).timeout
	if is_instance_valid(p):
		p.queue_free()


## 让某个按钮"被注意到"：撒一把粒子 + 轻微呼吸两下。
## 比原来一直硬闪的写法耐看，也不会一直抢注意力。
func attention(node: Control, color: Color = Color.WHITE) -> void:
	if node == null or not is_instance_valid(node):
		return
	sparkle(node, color)
	var tw := node.create_tween()
	tw.set_loops(2)
	tw.tween_property(node, "modulate:a", 0.4, 0.18)
	tw.tween_property(node, "modulate:a", 1.0, 0.22)


## ────────────────────────── 背景 ──────────────────────────

## 铺一层纵向渐变底色（纯代码生成，不需要美术资源），让开场/标题这类
## "整屏画面"有点纵深，不至于是一块死黑。调用时机放在最前面。
func add_backdrop(parent: Node, top: Color, bottom: Color) -> TextureRect:
	var grad := Gradient.new()
	grad.set_color(0, top)
	grad.set_color(1, bottom)

	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill_from = Vector2(0.5, 0.0)
	tex.fill_to = Vector2(0.5, 1.0)
	tex.width = 8
	tex.height = 128

	var rect := TextureRect.new()
	rect.texture = tex
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	parent.add_child(rect)
	return rect


## ────────────────────────── 氛围粒子 ──────────────────────────

## 在 parent 里加一层缓慢飘动的粒子。调用时机要放在背景色块之后、
## 内容之前，粒子才会被内容挡住（在"后面"）。
func add_ambient(parent: Node, color: Color, amount := 30) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.amount = amount
	p.lifetime = 10.0
	p.preprocess = 5.0            # 进场时就已经飘了一会儿，不会空一片
	p.local_coords = false
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.direction = Vector2(0, -1)
	p.spread = 40.0
	p.gravity = Vector2(0, 0)
	p.initial_velocity_min = 5.0
	p.initial_velocity_max = 16.0
	p.scale_amount_min = 1.5
	p.scale_amount_max = 3.5
	p.color = color

	var vp := _viewport_size(parent)
	p.position = vp * 0.5
	p.emission_sphere_radius = maxf(vp.x, vp.y) * 0.72
	parent.add_child(p)

	# 窗口尺寸变了，粒子的活动范围也跟着铺满
	var vp_node := parent.get_viewport()
	if vp_node != null:
		var cb := func() -> void:
			if not is_instance_valid(p) or not is_instance_valid(parent):
				return
			var s := _viewport_size(parent)
			p.position = s * 0.5
			p.emission_sphere_radius = maxf(s.x, s.y) * 0.72
		vp_node.size_changed.connect(cb)
		# 节点销毁时把连接摘掉，免得场景换多了在 viewport 上堆一堆死回调
		p.tree_exiting.connect(func() -> void:
			if vp_node.size_changed.is_connected(cb):
				vp_node.size_changed.disconnect(cb)
		)
	return p


func _viewport_size(node: Node) -> Vector2:
	var vp := node.get_viewport()
	if vp == null:
		return Vector2(1280, 720)
	return vp.get_visible_rect().size
