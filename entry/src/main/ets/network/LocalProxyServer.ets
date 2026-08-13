import { socket, connection } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { buffer } from '@kit.ArkTS';
import { Constants } from '../utils/Constants';
import { preferenceService } from '../services/PreferenceService';
import { hoster } from './Hoster';

interface ParsedRequest {
  host: string
  port: number
  headEnd: number
  isConnect: boolean
}

interface UpstreamOpen {
  sock: socket.TCPSocket
  handshake: boolean
  fragment: boolean
}

function sleep(ms: number): Promise<void> {
  return new Promise<void>((resolve) => {
    setTimeout(resolve, ms)
  })
}

function concatBytes(a: Uint8Array, b: Uint8Array): Uint8Array {
  let out = new Uint8Array(a.length + b.length)
  out.set(a, 0)
  out.set(b, a.length)
  return out
}

function findHeaderEnd(data: Uint8Array): number {
  for (let i = 0; i + 3 < data.length; i++) {
    if (data[i] === 13 && data[i + 1] === 10 && data[i + 2] === 13 && data[i + 3] === 10) {
      return i + 4
    }
  }
  return -1
}

function toArrayBuffer(bytes: Uint8Array): ArrayBuffer {
  let out = new ArrayBuffer(bytes.length)
  let view = new Uint8Array(out)
  view.set(bytes)
  return out
}

/**
 * 应用内本地代理中继：统一承载 Pixiv 流量，提供三种上游出口
 * （direct+DoH 绕过 / HTTP 代理 / SOCKS5 代理），实现免外部 VPN 访问。
 * 单例，随 EntryAbility 生命周期启动/停止。
 */
export class LocalProxyServer {
  private static instance: LocalProxyServer
  private server: socket.TCPSocketServer | null = null
  private running: boolean = false

  private constructor() {}

  static getInstance(): LocalProxyServer {
    if (!LocalProxyServer.instance) {
      LocalProxyServer.instance = new LocalProxyServer()
    }
    return LocalProxyServer.instance
  }

  isRunning(): boolean {
    return this.running
  }

  async start(): Promise<boolean> {
    if (this.running) {
      return true
    }
    try {
      this.server = socket.constructTCPSocketServerInstance()
      let address: socket.NetAddress = {
        address: Constants.LOCAL_PROXY_HOST,
        family: 1,
        port: Constants.LOCAL_PROXY_PORT
      }
      await this.server.listen(address)
      this.server.on('connect', (conn: socket.TCPSocketConnection) => {
        this.handleConnection(conn)
      })
      this.server.on('error', (err: BusinessError) => {
        console.error('LocalProxyServer error: ' + JSON.stringify(err))
      })
      this.running = true
      console.info('LocalProxyServer started on ' + Constants.LOCAL_PROXY_HOST + ':' + Constants.LOCAL_PROXY_PORT)
      return true
    } catch (e) {
      console.error('LocalProxyServer start failed: ' + e)
      this.server = null
      this.running = false
      return false
    }
  }

  async stop(): Promise<void> {
    this.running = false
    if (this.server) {
      try {
        await this.server.close()
      } catch (e) {
        console.error('LocalProxyServer stop failed: ' + e)
      }
      this.server = null
    }
  }

  private handleConnection(clientConn: socket.TCPSocketConnection): void {
    let upstream: socket.TCPSocket | null = null
    let closed: boolean = false
    let head: Uint8Array = new Uint8Array(0)
    let pending: ArrayBuffer[] = []
    let state: number = 0
    let fragmentFirst: boolean = false
    let firstRelayed: boolean = false
    let targetHost: string = ''

    let closeBoth = (): void => {
      if (closed) {
        return
      }
      closed = true
      try {
        clientConn.close()
      } catch (e) {
        console.error('close client failed: ' + e)
      }
      if (upstream) {
        try {
          upstream.close()
        } catch (e) {
          console.error('close upstream failed: ' + e)
        }
      }
    }

    let relayToUpstream = (data: ArrayBuffer): void => {
      if (!upstream) {
        return
      }
      let sock = upstream
      if (fragmentFirst && !firstRelayed) {
        firstRelayed = true
        this.sendFragmented(sock, data, targetHost).catch((e: Object) => {
          console.error('fragmented relay failed: ' + e)
          closeBoth()
        })
        return
      }
      sock.send({ data: data }).catch((e: Object) => {
        console.error('relay to upstream failed: ' + e)
        closeBoth()
      })
    }

    let flushPending = (): void => {
      if (!upstream) {
        return
      }
      let queue = pending.slice()
      pending = []
      for (let i = 0; i < queue.length; i++) {
        relayToUpstream(queue[i])
      }
    }

    let setupUpstreamRelay = (sock: socket.TCPSocket, needsHandshake: boolean, isConnect: boolean): void => {
      let handshakeDone = !needsHandshake
      let handshakeAcc = new Uint8Array(0)
      sock.on('message', (info: socket.SocketMessageInfo) => {
        if (closed) {
          return
        }
        if (!handshakeDone) {
          handshakeAcc = concatBytes(handshakeAcc, new Uint8Array(info.message))
          let idx = findHeaderEnd(handshakeAcc)
          if (idx < 0) {
            return
          }
          let headStr = this.bytesToString(handshakeAcc, 0, idx)
          if (headStr.indexOf(' 200 ') >= 0 || headStr.indexOf(' 200\r') >= 0) {
            handshakeDone = true
            if (idx < handshakeAcc.length) {
              clientConn.send({ data: toArrayBuffer(handshakeAcc.slice(idx)) }).catch((e: Object) => {
                console.error('send handshake leftover failed: ' + e)
              })
            }
          } else {
            console.error('proxy connect rejected: ' + headStr.split('\r\n')[0])
            closeBoth()
          }
          return
        }
        clientConn.send({ data: info.message }).catch((e: Object) => {
          console.error('relay to client failed: ' + e)
          closeBoth()
        })
      })
      sock.on('close', () => {
        closeBoth()
      })
      sock.on('error', (err: BusinessError) => {
        console.error('upstream socket error: ' + JSON.stringify(err))
        closeBoth()
      })
      if (isConnect) {
        clientConn.send({ data: this.stringToBuffer('HTTP/1.1 200 Connection Established\r\n\r\n') }).then(() => {
          state = 2
          flushPending()
        }).catch((e: Object) => {
          console.error('send connect ok failed: ' + e)
          closeBoth()
        })
      } else {
        state = 2
        flushPending()
      }
    }

    clientConn.on('message', (info: socket.SocketMessageInfo) => {
      if (closed) {
        return
      }
      if (state === 0) {
        head = concatBytes(head, new Uint8Array(info.message))
        let parsed = this.parseRequest(head)
        if (parsed === null) {
          return
        }
        let reqHost = parsed.host
        let reqPort = parsed.port
        let reqIsConnect = parsed.isConnect
        targetHost = reqHost
        let leftover = head.slice(parsed.headEnd)
        head = new Uint8Array(0)
        if (leftover.length > 0) {
          pending.push(toArrayBuffer(leftover))
        }
        state = 1
        this.openUpstream(reqHost, reqPort).then((result: UpstreamOpen) => {
          if (closed) {
            try {
              result.sock.close()
            } catch (e) {
              console.error('close unused upstream failed: ' + e)
            }
            return
          }
          upstream = result.sock
          fragmentFirst = result.fragment
          setupUpstreamRelay(result.sock, result.handshake, reqIsConnect)
        }).catch((e: Object) => {
          console.error('open upstream failed: ' + e)
          closeBoth()
        })
        return
      }
      if (state === 1) {
        pending.push(info.message)
        return
      }
      if (upstream) {
        relayToUpstream(info.message)
      }
    })

    clientConn.on('close', () => {
      closeBoth()
    })
    clientConn.on('error', (err: BusinessError) => {
      console.error('client socket error: ' + JSON.stringify(err))
      closeBoth()
    })
  }

  private parseRequest(data: Uint8Array): ParsedRequest | null {
    let end = findHeaderEnd(data)
    if (end < 0) {
      return null
    }
    let headStr = this.bytesToString(data, 0, end)
    let lines = headStr.split('\r\n')
    if (lines.length === 0) {
      return null
    }
    let parts = lines[0].split(' ')
    if (parts.length < 2) {
      return null
    }
    let method = parts[0]
    let target = parts[1]
    if (method === 'CONNECT') {
      let hostPort = target.split(':')
      if (hostPort.length < 2) {
        return null
      }
      let host = hostPort[0]
      let port = this.parsePort(hostPort[1], 443)
      if (host.length === 0) {
        return null
      }
      let result: ParsedRequest = { host: host, port: port, headEnd: end, isConnect: true }
      return result
    }
    let host = ''
    let port = 80
    for (let i = 1; i < lines.length; i++) {
      let line = lines[i]
      let colon = line.indexOf(':')
      if (colon > 0) {
        let key = line.substring(0, colon).trim().toLowerCase()
        if (key === 'host') {
          let value = line.substring(colon + 1).trim()
          let hp = value.split(':')
          host = hp[0]
          if (hp.length > 1) {
            port = this.parsePort(hp[1], 80)
          }
          break
        }
      }
    }
    if (host.length === 0) {
      let uri = target
      if (uri.startsWith('http://')) {
        uri = uri.substring(7)
      } else if (uri.startsWith('https://')) {
        uri = uri.substring(8)
      }
      let slash = uri.indexOf('/')
      if (slash >= 0) {
        uri = uri.substring(0, slash)
      }
      let hp = uri.split(':')
      host = hp[0]
      if (hp.length > 1) {
        port = this.parsePort(hp[1], 80)
      }
    }
    if (host.length === 0) {
      return null
    }
    let result: ParsedRequest = { host: host, port: port, headEnd: end, isConnect: false }
    return result
  }

  private parsePort(s: string, fallback: number): number {
    let p = Number(s)
    if (Number.isNaN(p) || p <= 0 || p > 65535) {
      return fallback
    }
    return Math.floor(p)
  }

  private resolveModeForHost(host: string): string {
    if (host === 'oauth.secure.pixiv.net') {
      return Constants.normalizeMode(preferenceService.getString('auth_mode', Constants.MODE_STANDARD))
    }
    if (host === 'app-api.pixiv.net' || host === 'public-api.secure.pixiv.net') {
      return Constants.normalizeMode(preferenceService.getString('api_mode', Constants.MODE_STANDARD))
    }
    return Constants.MODE_COMPATIBLE
  }

  private async openUpstream(host: string, port: number): Promise<UpstreamOpen> {
    let mode = this.resolveModeForHost(host)
    console.info('[LocalProxy] ' + host + ':' + port + ' mode=' + mode)
    let result = await this.openDirect(host, port)
    result.fragment = (mode === Constants.MODE_ECH)
    return result
  }

  private async openDirect(host: string, port: number): Promise<UpstreamOpen> {
    let tcp = socket.constructTCPSocketInstance()
    let ip = await this.resolveHostIp(host)
    let address: socket.NetAddress = { address: ip, family: 1, port: port }
    await tcp.connect({ address: address, timeout: 30000 })
    try {
      let extra: socket.TCPExtraOptions = { TCPNoDelay: true }
      await tcp.setExtraOptions(extra)
    } catch (e) {
      console.error('set TCPNoDelay failed: ' + e)
    }
    let result: UpstreamOpen = { sock: tcp, handshake: false, fragment: false }
    return result
  }

  private async openSocks5(host: string, port: number): Promise<UpstreamOpen> {
    let proxyHost = preferenceService.getString('proxy_host', '')
    if (proxyHost.length === 0) {
      throw new Error('proxy host not configured')
    }
    let tcp = socket.constructTCPSocketInstance()
    let ip = await this.resolveHostIp(host)
    let target: socket.NetAddress = { address: ip, family: 1, port: port }
    let proxyAddr: socket.NetAddress = {
      address: proxyHost,
      family: 1,
      port: preferenceService.getNumber('proxy_port', 1080)
    }
    let proxy: socket.ProxyOptions = { type: socket.ProxyTypes.SOCKS5, address: proxyAddr }
    let proxyUser = preferenceService.getString('proxy_username', '')
    if (proxyUser.length > 0) {
      proxy.username = proxyUser
      proxy.password = preferenceService.getString('proxy_password', '')
    }
    await tcp.connect({ address: target, timeout: 30000, proxy: proxy })
    let result: UpstreamOpen = { sock: tcp, handshake: false, fragment: false }
    return result
  }

  private async openHttpProxy(host: string, port: number): Promise<UpstreamOpen> {
    let proxyHost = preferenceService.getString('proxy_host', '')
    if (proxyHost.length === 0) {
      throw new Error('proxy host not configured')
    }
    let tcp = socket.constructTCPSocketInstance()
    let proxyAddr: socket.NetAddress = {
      address: proxyHost,
      family: 1,
      port: preferenceService.getNumber('proxy_port', 1080)
    }
    await tcp.connect({ address: proxyAddr, timeout: 30000 })
    let connectReq = 'CONNECT ' + host + ':' + port + ' HTTP/1.1\r\n' +
      'Host: ' + host + ':' + port + '\r\n'
    let proxyUser = preferenceService.getString('proxy_username', '')
    if (proxyUser.length > 0) {
      connectReq += 'Proxy-Authorization: Basic ' +
        this.base64Encode(proxyUser + ':' + preferenceService.getString('proxy_password', '')) + '\r\n'
    }
    connectReq += '\r\n'
    await tcp.send({ data: connectReq })
    let result: UpstreamOpen = { sock: tcp, handshake: true, fragment: false }
    return result
  }

  /** SNI 分片：把 ClientHello 拆成两个 TCP 段发送，规避 GFW 对首个包内 SNI 的检测 */
  private async sendFragmented(sock: socket.TCPSocket, data: ArrayBuffer, host: string): Promise<void> {
    let bytes = new Uint8Array(data)
    if (bytes.length <= 2) {
      await sock.send({ data: data })
      return
    }
    let snipos = this.findBytes(bytes, host)
    let splitAt = 1
    if (snipos >= 0) {
      splitAt = snipos + Math.floor(host.length / 2)
      if (splitAt < 1) {
        splitAt = 1
      }
      if (splitAt >= bytes.length) {
        splitAt = bytes.length - 1
      }
    }
    console.info('[LocalProxy] fragment ClientHello len=' + bytes.length + ' split=' + splitAt)
    let first = toArrayBuffer(bytes.slice(0, splitAt))
    let rest = toArrayBuffer(bytes.slice(splitAt))
    await sock.send({ data: first })
    await sleep(30)
    await sock.send({ data: rest })
  }

  private findBytes(data: Uint8Array, needle: string): number {
    let needleBytes: number[] = []
    for (let i = 0; i < needle.length; i++) {
      needleBytes.push(needle.charCodeAt(i) & 0xFF)
    }
    for (let i = 0; i + needleBytes.length <= data.length; i++) {
      let match = true
      for (let j = 0; j < needleBytes.length; j++) {
        if (data[i + j] !== needleBytes[j]) {
          match = false
          break
        }
      }
      if (match) {
        return i
      }
    }
    return -1
  }

  private async resolveHostIp(host: string): Promise<string> {
    let ips = hoster.resolveIps(host)
    if (ips.length > 0 && ips[0].length > 0) {
      return ips[0]
    }
    try {
      let addrs = await connection.getAddressesByName(host)
      if (addrs.length > 0 && addrs[0].address.length > 0) {
        return addrs[0].address
      }
    } catch (e) {
      console.error('resolve host ' + host + ' failed: ' + e)
    }
    return host
  }

  private bytesToString(bytes: Uint8Array, start: number, end: number): string {
    let chars: string[] = []
    for (let i = start; i < end; i++) {
      chars.push(String.fromCharCode(bytes[i]))
    }
    return chars.join('')
  }

  private stringToBuffer(s: string): ArrayBuffer {
    let bytes = new Uint8Array(s.length)
    for (let i = 0; i < s.length; i++) {
      bytes[i] = s.charCodeAt(i) & 0xFF
    }
    return bytes.buffer
  }

  private base64Encode(s: string): string {
    return buffer.from(s, 'utf-8').toString('base64')
  }
}

export const localProxyServer = LocalProxyServer.getInstance()
