/// 브라우저 로그인(Device Flow)에 쓰는 GitHub OAuth App의 Client ID.
/// 비밀이 아니다. 빌드할 때 `--dart-define=NOTES2HUB_GITHUB_CLIENT_ID=<id>`로 넣는다.
/// 비어 있으면 앱은 토큰 입력 로그인만 보여준다.
const kGitHubClientId = String.fromEnvironment('NOTES2HUB_GITHUB_CLIENT_ID');
