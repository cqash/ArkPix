import { HttpClient } from './HttpClient';
import { PixivEndpoints } from './PixivEndpoints';
import { Constants } from '../utils/Constants';
import { CryptoUtils } from '../utils/CryptoUtils';
import { authInterceptor } from './AuthInterceptor';

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

interface AuthHeaders {
  'Content-Type': string
  'User-Agent': string
  'X-Client-Time': string
  'X-Client-Hash': string
}

export class OAuthService {
  private static instance: OAuthService
  private httpClient: HttpClient

  private constructor() {
    this.httpClient = HttpClient.getInstance()
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

    let response = await this.httpClient.post(PixivEndpoints.OAUTH_TOKEN_URL, body, {
      'Content-Type': 'application/x-www-form-urlencoded',
      'User-Agent': Constants.USER_AGENT,
      'X-Client-Time': CryptoUtils.getIsoDate(),
      'X-Client-Hash': CryptoUtils.md5(CryptoUtils.getIsoDate() + Constants.HASH_SALT)
    })

    let result = JSON.parse(String(response.result)) as TokenResponse
    authInterceptor.setTokens(result.access_token, result.refresh_token)
    return result
  }

  async refreshToken(refreshToken: string): Promise<TokenResponse> {
    let body = 'grant_type=refresh_token' +
      '&refresh_token=' + refreshToken +
      '&client_id=' + Constants.REFRESH_CLIENT_ID +
      '&client_secret=' + Constants.REFRESH_CLIENT_SECRET

    let response = await this.httpClient.post(PixivEndpoints.OAUTH_TOKEN_URL, body, {
      'Content-Type': 'application/x-www-form-urlencoded',
      'User-Agent': Constants.USER_AGENT,
      'X-Client-Time': CryptoUtils.getIsoDate(),
      'X-Client-Hash': CryptoUtils.md5(CryptoUtils.getIsoDate() + Constants.HASH_SALT)
    })

    let result = JSON.parse(String(response.result)) as TokenResponse
    authInterceptor.setTokens(result.access_token, result.refresh_token)
    return result
  }
}

export const oauthService = OAuthService.getInstance()
