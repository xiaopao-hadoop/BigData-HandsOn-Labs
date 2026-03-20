# Define your item pipelines here
#
# Don't forget to add your pipeline to the ITEM_PIPELINES setting
# See: https://docs.scrapy.org/en/latest/topics/item-pipeline.html

# useful for handling different item types with a single interface
from itemadapter import ItemAdapter
from scrapy.exceptions import DropItem

import json
import redis
import logging
from pykafka import KafkaClient
from .items import HouseItemModel
from pydantic import ValidationError


class KafkaRedisPipeline:
    def __init__(self, kafka_hosts, kafka_topic, redis_host, redis_port):
        self.kafka_hosts = kafka_hosts
        self.kafka_topic_name = kafka_topic
        self.redis_host = redis_host
        self.redis_port = redis_port
        self.logger = logging.getLogger(__name__)

    @classmethod
    def from_crawler(cls, crawler):
        # 从 settings.py 中读取配置参数
        return cls(
            kafka_hosts=crawler.settings.get('KAFKA_HOSTS'),
            kafka_topic=crawler.settings.get('KAFKA_TOPIC'),
            redis_host=crawler.settings.get('REDIS_HOST'),
            redis_port=crawler.settings.get('REDIS_PORT')
        )

    def open_spider(self, spider):
        """爬虫启动时：初始化 Kafka 生产者和 Redis 连接"""
        # 1. 连接 Redis
        self.redis_client = redis.Redis(
            host=self.redis_host,
            port=self.redis_port,
            decode_responses=True 
        )
        self.redis_set_key = "ershoufang:completed_house_ids"

        # 2. 连接 Kafka
        try:
            self.kafka_client = KafkaClient(hosts=self.kafka_hosts)
            self.topic = self.kafka_client.topics[self.kafka_topic_name.encode('utf-8')]
            # 使用同步生产者，保证数据确实发过去了再记录 Redis
            self.producer = self.topic.get_sync_producer()
            self.logger.info("Kafka 和 Redis 连接成功！")
        except Exception as e:
            self.logger.error(f"中间件连接失败: {e}")
            raise e

    def close_spider(self, spider):
        """爬虫关闭时：清理连接"""
        if hasattr(self, 'producer'):
            self.producer.stop()
        if hasattr(self, 'redis_client'):
            self.redis_client.close()

    def process_item(self, item, spider):
        """处理每一条抓取到的数据"""
        house_id = item.get('core_data', {}).get('house_id')

        # 检查 Redis 是否已经有这条数据了
        if self.redis_client.sismember(self.redis_set_key, house_id):
            self.logger.debug(f"数据已存在于Kafka，跳过: {house_id}")
            return item

        try:
            # 1. Pydantic 数据校验
            # 这行代码如果不报错，说明数据符合规范
            valid_item = HouseItemModel(**item)

            # 2. 序列化为 JSON 字符串并推送到 Kafka
            json_data = valid_item.model_dump_json()  # Pydantic V2 语法，如果用 V1 则是 json()
            self.producer.produce(json_data.encode('utf-8'))

            # 3. 成功发送 Kafka 后，将 house_id 写入 Redis Set
            self.redis_client.sadd(self.redis_set_key, house_id)
            self.logger.info(f"成功推送至 Kafka 并记录 Redis: {house_id}")

        except ValidationError as e:
            # 如果校验失败，打印错误日志，不发送到 Kafka，防止污染数据队列
            self.logger.error(f"Pydantic 校验失败，抛弃脏数据 house_id: {house_id}。错误详情: {e}")
        except Exception as e:
            self.logger.error(f"推送到 Kafka 时发生异常: {e}")

        return item