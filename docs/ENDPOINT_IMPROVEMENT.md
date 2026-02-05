# 背景描述

目前在程序中，我们固定配置了openai和google-genai两种不同的channel。
同时在管理模型时，会选择一个channel并添加。

这个情况下的用户只能固定添加这两种channel以及模型，影响了灵活性。

## 需求

1. 从 settings中移除channel的配置
2. 增强model_screen配置能力。拆分为2个tab
   1. tab1 为model 管理，这里按照channel分组，展示其下模型，分组可以折叠展开
   2. 分组上保留当前fetch Model的功能，可以直接从该分组检索模型。
      1. 检索功能加入关键字过滤功能，增加用户体验
   3. tab2 为channel管理，用户可以在其中添加或者删除或者编辑channel，详细见**Channel管理**章节

## Channel管理

现在用户可以自由添加/编辑/删除 channel。
channel的配置有以下几个关键点
1. endpoint地址
2. apikey
3. 访问类型
   1. google-gen-api，该channel的访问方式为`google-genai-rest`, 对应当前`google_genai_provider.dart`的实现
   2. openai-api，该channel的访问方式为`openai-api-rest`, 对应当前`openai_api_provider.dart`的实现
   3. official-google-genai-api，与google-gen-api，不过这里只需要配置apikey即可，其他采用google官方实现（`google_genai_provider.dart`中有相关实现，主要是认证头与其他三方不一样）
4. 是否启用模型检索，勾选后会在model 管理中允许fetch Model的功能
5. 显示名称，作为分组名称
6. tag（可选），用于在dropbox中显示该channel模型的标识，并且可以选择一个颜色作为tag的颜色（默认自动随机一个色彩）

