## 📦 数据来源与 Schema 定义 

本项目的原始数据来源于国内某头部二手房交易网站的公开房源信息，约45w条。为聚焦于大数据流处理与数仓建模核心链路，**此处不提供负责网页 DOM 解析的核心 Scrapy 爬虫脚本**。
可以参考提供的数据管道脚本（[`pipelines.py`](https://github.com/xiaopao-hadoop/BigData-HandsOn-Labs/blob/main/housing-data-warehouse/data/pipelines.py)），该脚本展示了如何将非结构化网页数据进行清洗、序列化，并作为 Producer 实时写入 **Kafka** 消息队列。

### 1. 静态数据集 (Kaggle Dataset)
为了方便复现整个数仓链路，无需重新运行爬虫，我已经将清洗后的全量原始数据打包上传至 Kaggle。
*  **数据集下载地址**：https://www.kaggle.com/datasets/xiaopaohadoop/second-hand-housing-dataset

### 2. 数据模型与契约 (Data Schema)
流入 Kafka 的消息采用**多层嵌套的 JSON 格式**。为了保证数据质量与下游（Flink/Spark）计算引擎的强类型安全，数据在生成端采用了 Python `Pydantic` 库进行严格的 Schema 校验。

单条房源数据（`HouseRecord`）包含三个逻辑层级：**元数据头 (Header)**、**核心业务数据 (CoreData)** 与 **扩展属性 (ExtAttributes)**。

#### 核心数据结构说明

**Level 1: 顶层结构**
| 字段名 | 类型 | 说明 |
| :--- | :--- | :--- |
| `header` | Object | 消息元数据，包含时间戳、溯源追踪 |
| `core_data` | Object | 房源核心业务字段（价格、面积等） |
| `ext_attributes` | Object | 房源扩展与长尾标签 |

**Level 2: 核心业务数据**
| 字段名 | 类型 | 校验规则/默认值 | 业务含义 |
| :--- | :--- | :--- | :--- |
| `house_id` | String | 必填 | 房源全局唯一标识 |
| `city` / `district` | String | 必填 | 城市与行政区 |
| `total_price` | Float | **强校验 (必须为数字)** | 房屋总价 (万元) |
| `unit_price` | Float | 必填 | 房屋单价 (元/平米) |
| `area_sqm` | Float | 必填 | 建筑面积 (平米) |
| `room_num` / `hall_num` | Integer | 默认为 0 | 几室 / 几厅 |
| `build_year` | Integer | Optional | 建筑年份 |

*(注：其他如 `biz_circle` (商圈)、`direction` (朝向)、`floor_level` (楼层) 等非强依赖字段允许为空，以容忍源端数据的脏乱。)*

<details>
<summary>点击查看完整的 Pydantic 校验类源码</summary>

```python
from pydantic import BaseModel, Field
from typing import Optional, List, Dict
import time, uuid

class Header(BaseModel):
    source: str
    event_time: int = Field(default_factory=lambda: int(time.time()))
    version: str = "1.1"
    trace_id: str = Field(default_factory=lambda: str(uuid.uuid4()))

class CoreData(BaseModel):
    house_id: str
    url: str
    title: Optional[str] = None
    city: str
    district: str
    biz_circle: Optional[str] = None
    community: str
    total_price: float       # 强校验：必须是数字
    unit_price: float
    area_sqm: float
    room_num: int = 0
    hall_num: int = 0
    kitchen_num: int = 0
    bathroom_num: int = 0
    direction: Optional[str] = None
    floor_level: Optional[str] = None
    total_floors: int = 0
    build_year: Optional[int] = None
    decoration: Optional[str] = None

class ExtAttributes(BaseModel):
    tags: List[str] = Field(default_factory=list)
    raw_info: Dict[str, str] = Field(default_factory=dict)

class HouseRecord(BaseModel):
    header: Header
    core_data: CoreData
    ext_attributes: ExtAttributes