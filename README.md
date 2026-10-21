# bwh45 REALITY installer

专用于 bwh45 的 Linux x86_64 / CentOS 7 安装脚本。协议为 VLESS + TCP + REALITY + xtls-rprx-vision。使用官方 Xray v26.3.27，固定并核对官方发布包 SHA256。

## 安装

先停止或卸载占用 TCP 443 的旧代理/Caddy。在 VPS 的 root 终端执行：

~~~bash
bash <(curl -fsSL https://raw.githubusercontent.com/elastelzhou-web/test/main/install.sh)
~~~

脚本使用当前 VPS 的公网 IPv4 导出节点，自动尝试候选 REALITY 握手目标；生成独立 UUID、密钥和 ShortId。在写入服务前运行临时 REALITY 服务端/客户端进行真实 HTTPS 代理测试；启动正式 systemd 服务后，再通过正式入站重复测试。只有这些检查通过才报告安装成功。主机防火墙仅添加节点 TCP 端口规则。

CentOS 7 使用已有 curl、Python 2.7（或 Python 3）、iproute、coreutils 和 systemd，不依赖 APT、不运行失效的 yum 仓库、不用旧系统 OpenSSL 实现 TLS 1.3 探测。已有其他服务和 SSH 端口保持原配置。

## 使用

安装成功后将终端输出的完整 VLESS 链接导入 v2rayN。连接信息与客户端配置在 /root/bwh45-reality-client.txt 和 /etc/bwh45-reality/client.json；文件均仅 root 可读。服务名称 bwh45-reality.service。

~~~bash
bash <(curl -fsSL https://raw.githubusercontent.com/elastelzhou-web/test/main/install.sh) --check
bash <(curl -fsSL https://raw.githubusercontent.com/elastelzhou-web/test/main/install.sh) --uninstall
~~~

重复运行安装会复用已有凭据并检查连接，不会生成第二套节点。卸载会保留备份。

可选环境变量：SERVER_ADDRESS（连接地址，默认实际公网 IPv4）、SNI（固定握手域名，默认自动选择）、PORT（默认 443）、FINGERPRINT（默认 chrome，可选 ios）。

## 验证范围

测试将覆盖密钥格式兼容、校验和拒绝、地址/配置生成、CentOS 7 的 Bash/Python 2 兼容，以及使用真实官方 Xray 的 REALITY/Vision HTTPS 代理。测试和结果见 Actions。

安装时的服务器自测验证该 VPS 上的核心、配置、握手目标与出站链路。客户端所在网络到 VPS 的公网路径、服务商防火墙和 OpenAI 对出口 IP 的限制仍需客户端验证；脚本不会把这些未测项目标成通过。


默认候选为 Amazon、Google 下载站与 Cloudflare，并逐个通过真实代理验证后才采用。Microsoft 未列入默认候选：Xray 26.3.27 存在特定 Microsoft 证书记录超过 REALITY 内部上限的已知握手问题，普通 TLS 探测通过并不代表 REALITY 可用。参考：https://github.com/XTLS/Xray-core/issues/6356

## 参考

- https://github.com/XTLS/Xray-install
- https://github.com/XTLS/REALITY/blob/main/README.en.md
- https://github.com/XTLS/Xray-examples/tree/main/VLESS-TCP-XTLS-Vision-REALITY
- https://github.com/XTLS/Xray-core/releases/tag/v26.3.27
- https://github.com/skylink9119/skybyte-xray-manager/tree/v0.1.12

本项目为独立实现，仅参考上述项目的配置与操作方式；不复制它们的安装器源码。

用户提供的补充参考：https://github.com/cholf5/random/issues/38 （其 Ubuntu 系统优化步骤未直接移植到 CentOS 7）。
