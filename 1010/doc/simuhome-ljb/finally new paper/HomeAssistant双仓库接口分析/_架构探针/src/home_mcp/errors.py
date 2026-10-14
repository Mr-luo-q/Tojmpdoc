"""统一错误类型：协议层与后端共用。"""


class HomeMcpError(Exception):
    """本项目所有自定义错误的基类。"""


class MissingToolsError(HomeMcpError):
    """后端实现的工具集合与契约不一致时抛出。"""
