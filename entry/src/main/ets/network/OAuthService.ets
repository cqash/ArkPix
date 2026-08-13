import { socket } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { PixivEndpoints } from './PixivEndpoints';
import { Constants } from '../utils/Constants';
import { CryptoUtils } from '../utils/CryptoUtils';
import { authInterceptor } from './AuthInterceptor';

/** 凭证失效：服务端明确拒绝 refresh token，必须重新登录 */
export class CredentialInvalidError extends Error {
  constructor(message: string) {
    super(message)
    this.name = 'CredentialInvalidError'
  }
}

/** 网络错误：临时故障（超时/5xx/解析失败），可重试，不应登出 */
export class NetworkError extends Error {
  constructor(message: string) {
    super(message)
    this.name = 'NetworkError'
  }
}

interface ProfileImageUrls {
  px_16x16?: string
  px_50x50?: string
  px_170x170?: string
}

interface UserInfo {
  id: string
  name: string
  account: string
  profile_image_urls: ProfileImageUrls
}

interface TokenResponse {
  access_token: string
  refresh_token: string
  user: UserInfo
}

/** 刷新接口原始响应（错误响应为合法 JSON 但无 token 字段） */
interface RawTokenResponse {
  access_token?: string
  refresh_token?: string
  user?: UserInfo
}

interface AuthHeaders {
  'Content-Type': string
  'User-Agent': string
  'X-Client-Time': string
  'X-Client-Hash': string
}

interface NoSniResponse {
  code: number
  body: string
}

export class OAuthService {
  private static instance: OAuthService

  private constructor() {
  }

  static getInstance(): OAuthService {
    if (!OAuthService.instance) {
      OAuthService.instance = new OAuthService()
    }
    return OAuthService.instance
  }

  getAuthUrl(codeChallenge: string): string {
    let url = PixivEndpoints.OAUTH_AUTH_URL +
      '?code_challenge=' + codeChallenge +
      '&code_challenge_method=S256&client=pixiv-android'
    return Constants.applyProxy(url)
  }

  async exchangeToken(code: string, codeVerifier: string): Promise<TokenResponse> {
    let body = 'grant_type=authorization_code' +
      '&code=' + code +
      '&code_verifier=' + codeVerifier +
      '&client_id=' + Constants.CLIENT_ID +
      '&client_secret=' + Constants.CLIENT_SECRET +
      '&redirect_uri=' + encodeURIComponent(Constants.REDIRECT_URI)

    let response = await this.postTokenNoSni(body)
    if (response.code !== 200) {
      throw new Error('exchange token failed: ' + response.code + ' ' + response.body)
    }

    let result = JSON.parse(response.body) as TokenResponse
    authInterceptor.setTokens(result.access_token, result.refresh_token)
    return result
  }

  async refreshToken(refreshToken: string): Promise<TokenResponse> {
    // 刷新必须使用与签发时相同的 client 凭证（exchangeToken 用 CLIENT_ID），
    // 否则服务端按 invalid_client 返回 400，导致刷新永远失败（历史"掉登录"根因）
    let body = 'grant_type=refresh_token' +
      '&refresh_token=' + refreshToken +
      '&client_id=' + Constants.CLIENT_ID +
      '&client_secret=' + Constants.CLIENT_SECRET

    // 网络层异常（超时/断网）归类为临时错误，不做登出处理
    let response: NoSniResponse
    try {
      response = await this.postTokenNoSni(body)
    } catch (e) {
      throw new NetworkError('刷新 token 网络请求失败: ' + e)
    }

    if (response.code !== 200) {
      console.error('OAuth refresh response: ' + response.code + ' ' + response.body)
      if (response.code === 400 || response.code === 401 || response.code === 403) {
        throw new CredentialInvalidError('登录凭证已被服务端拒绝 (HTTP ' + response.code + ')')
      }
      throw new NetworkError('刷新 token 服务器错误 (HTTP ' + response.code + ')')
    }

    let raw: RawTokenResponse
    try {
      raw = JSON.parse(response.body) as RawTokenResponse
    } catch (e) {
      throw new NetworkError('刷新 token 响应解析失败: ' + e)
    }

    // 有效性校验通过前不写回任何 token，杜绝错误 JSON 静默写坏登录态
    if (raw.access_token === undefined || raw.access_token.length === 0 ||
      raw.user === undefined || raw.user.id.length === 0) {
      throw new CredentialInvalidError('刷新 token 响应无效（缺少 access_token），请重新登录')
    }

    let result: TokenResponse = {
      access_token: raw.access_token,
      refresh_token: raw.refresh_token ?? refreshToken,
      user: raw.user
    }
    authInterceptor.setTokens(result.access_token, result.refresh_token)
    return result
  }

  private async postTokenNoSni(body: string): Promise<NoSniResponse> {
    let headerStr = 'Host: oauth.secure.pixiv.net\r\n' +
      'Content-Type: application/x-www-form-urlencoded\r\n' +
      'User-Agent: ' + Constants.USER_AGENT + '\r\n' +
      'X-Client-Time: ' + CryptoUtils.getIsoDate() + '\r\n' +
      'X-Client-Hash: ' + CryptoUtils.md5(CryptoUtils.getIsoDate() + Constants.HASH_SALT) + '\r\n' +
      'Content-Length: ' + body.length + '\r\n' +
      'Connection: close'
    return this.doNoSniPost(Constants.DIRECT_IP_OAUTH, '/auth/token', headerStr, body)
  }

  private doNoSniPost(ip: string, path: string, headerStr: string, body: string): Promise<NoSniResponse> {
    return new Promise<NoSniResponse>((resolve, reject) => {
      let tls = socket.constructTLSSocketInstance()
      let acc = new Uint8Array(0)
      let settled = false
      let reqStr = 'POST ' + path + ' HTTP/1.1\r\n' + headerStr + '\r\n\r\n' + body
      tls.on('message', (info: socket.SocketMessageInfo) => {
        acc = this.concatBytesLocal(acc, new Uint8Array(info.message))
      })
      tls.on('close', () => {
        if (settled) {
          return
        }
        settled = true
        resolve(this.parseHttpResponse(acc))
      })
      tls.on('error', (err: BusinessError) => {
        if (settled) {
          return
        }
        settled = true
        reject(new Error('TLS error: ' + JSON.stringify(err)))
      })
      tls.connect({
        address: { address: ip, family: 1, port: 443 },
        secureOptions: {}
      }).then(() => {
        return tls.send(reqStr)
      }).catch((e: Object) => {
        if (!settled) {
          settled = true
          reject(new Error('TLS connect/send failed: ' + e))
        }
      })
    })
  }

  private concatBytesLocal(a: Uint8Array, b: Uint8Array): Uint8Array {
    let out = new Uint8Array(a.length + b.length)
    out.set(a, 0)
    out.set(b, a.length)
    return out
  }

  private bytesToString(bytes: Uint8Array): string {
    let chars: string[] = []
    for (let i = 0; i < bytes.length; i++) {
      chars.push(String.fromCharCode(bytes[i]))
    }
    return chars.join('')
  }

  private parseHttpResponse(bytes: Uint8Array): NoSniResponse {
    let str = this.bytesToString(bytes)
    let headerEnd = str.indexOf('\r\n\r\n')
    let head = headerEnd >= 0 ? str.substring(0, headerEnd) : str
    let body = headerEnd >= 0 ? str.substring(headerEnd + 4) : ''
    let lines = head.split('\r\n')
    let code = 0
    if (lines.length > 0) {
      let parts = lines[0].split(' ')
      if (parts.length >= 2) {
        let n = Number(parts[1])
        if (!Number.isNaN(n)) {
          code = Math.floor(n)
        }
      }
    }
    let result: NoSniResponse = { code: code, body: body }
    return result
  }
}

export const oauthService = OAuthService.getInstance()
