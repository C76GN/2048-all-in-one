## GameSceneRouterPort: 跨 Feature 的场景路由 Interface。
##
## Feature 只提交稳定场景意图；navigation 提供唯一 Adapter，并继续拥有加载、
## 转场、取消、超时和退出生命周期。Composition Root 必须把同一个
## SceneRouterSystem 实例直接注册为本 Port 的 System alias。
class_name GameSceneRouterPort
extends GFSystem


# --- 公共方法 ---

## 切换到指定的绝对 .tscn 资源路径。
## @param _path: 待切换的稳定场景资源路径。
func goto_scene(_path: String) -> void:
	push_error("[GameSceneRouterPort] 未安装 navigation Adapter，无法切换场景。")


## 返回项目主菜单。
func return_to_main_menu() -> void:
	push_error("[GameSceneRouterPort] 未安装 navigation Adapter，无法返回主菜单。")
