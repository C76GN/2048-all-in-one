# scripts/models/game_status_model.gd

## GameStatusModel: 负责游戏运行时的状态统计 (分数、步数、击杀数等)。
class_name GameStatusModel
extends GFModel


# --- 公共变量 ---

## 当前分数
var score: BindableProperty = BindableProperty.new(0)

## 最高分
var high_score: BindableProperty = BindableProperty.new(0)

## 最大方块值
var highest_tile: BindableProperty = BindableProperty.new(0)

## 游戏中的移动总步数。
var move_count: BindableProperty = BindableProperty.new(0)

## 游戏中击杀的怪物数量。
var monsters_killed: BindableProperty = BindableProperty.new(0)

## 顶端状态消息
var status_message: BindableProperty = BindableProperty.new("")

## 规则特定的额外统计数据 (Dictionary 或 Array)
var extra_stats: BindableProperty = BindableProperty.new({})


# --- Godot 生命周期方法 ---

func init() -> void:
	super.init()


func async_init() -> void:
	super.async_init()


func ready() -> void:
	super.ready()
