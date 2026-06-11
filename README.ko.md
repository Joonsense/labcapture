# LabCapture

[English](README.md) | **한국어** | [简体中文](README.zh-CN.md) | [日本語](README.ja.md) | [Español](README.es.md)

**플로우를 깨지 않는 build-in-public.**

빌딩 작업 중 주기적으로 **화면 + 얼굴(웹캠)** 을 약 3초씩 캡처해, 콘텐츠 소재용 **GIF 3종 + 고화질 원본 mp4**를 자동 생성하는 macOS 메뉴바 앱. 하루가 끝나면 1080p 타임랩스(화면 배경 + 얼굴 원형 중앙 오버레이)와 AI 빌딩 일지가 만들어진다. 전부 로컬 — 계정도, 업로드도, 텔레메트리도 없다.

파일명은 모두 `YYYY-MM-DD_HHmmss` (날짜+시간) 기반:

- `{날짜_시간}_screen.gif` — 화면만 (가로 960px)
- `{날짜_시간}_face.gif` — 얼굴만 (가로 480px)
- `{날짜_시간}_combo.gif` — 화면 + 얼굴 **원형 PiP** 합성 (라임 `#A3E635` 링, 5MB 초과 시 720px 자동 다운스케일)
- `{날짜_시간}_screen.mp4` / `_face.mp4` — 고화질 원본 (crf 18, 30fps — 타임랩스 재료)

세 GIF 모두 좌하단에 캡처 시각(`YYYY-MM-DD HH:mm:ss`)이 라임 그린으로 표시된다.

## 요구 환경

- macOS 14+ (Apple Silicon)
- ffmpeg: `brew install ffmpeg`
- Xcode Command Line Tools (빌드 시)

## 빌드 & 실행

```bash
git clone https://github.com/Joonsense/labcapture.git
cd labcapture
./build.sh
open dist/LabCapture.app
```

메뉴바에 라임색 점이 나타나면 실행된 것. Dock 아이콘은 없다 (`LSUIElement`).

## 권한 설정 (최초 1회 — 중요)

첫 실행 시 온보딩 창이 권한 체크리스트를 보여준다. 각 항목의 "설정 열기"로 시스템 설정 해당 패널이 바로 열린다.

| 권한 | 위치 | 용도 |
|---|---|---|
| 화면 기록 | 개인정보 보호 → 화면 기록 | 화면 캡처 (필수) |
| 카메라 | 개인정보 보호 → 카메라 | 얼굴 캡처 (웹캠 OFF면 불필요) |
| 알림 | 알림 | "캡처 3초 전" 사전 알림 |

주의사항:

- ffmpeg는 서브프로세스로 실행되므로 TCC 권한은 **LabCapture.app 기준**으로 묻는다. 앱에 권한을 주면 ffmpeg도 동작한다.
- **Xcode/터미널에서 직접 실행할 때와 빌드된 .app으로 실행할 때 권한이 별개로 잡힐 수 있다.** 반드시 `dist/LabCapture.app`을 실행한 상태에서 권한을 허용할 것.
- 권한 미허용 상태에서는 캡처가 크래시 없이 skip되고 알림으로 안내한다.

### 서명과 TCC — 재빌드해도 권한이 유지되는 이유 (v0.4+)

ad-hoc 서명(`codesign -s -`)은 빌드마다 CDHash(지문)가 바뀌어 **화면 기록 권한이 매번 풀렸다**.
설정 화면엔 ON으로 보여도 TCC 레코드가 옛 지문을 가리켜 실제로는 거부된다 (증상: ffmpeg
`Configuration of video device failed`). 이때는 `tccutil reset ScreenCapture com.deblockx.labcapture`
후 재허용해야 한다.

v0.4부터 자체 서명 인증서 **"LabCapture Dev"**(10년 유효)로 서명한다. designated requirement가
`identifier + certificate leaf`가 되어 **재빌드해도 권한이 유지된다**. build.sh가 키체인에서
인증서를 자동 감지하며, 없으면 ad-hoc으로 폴백한다.

인증서 재생성이 필요할 때 (키체인 분실 등):

```bash
PASS=$(cat ~/.config/labcapture/sign_keychain_pass)  # 없으면 openssl rand -hex 16 으로 새로 생성
cd /tmp
openssl req -x509 -newkey rsa:2048 -keyout lc_key.pem -out lc_cert.pem -days 3650 -nodes \
  -subj "/CN=LabCapture Dev" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning" \
  -addext "basicConstraints=critical,CA:FALSE"
openssl pkcs12 -export -legacy -out lc.p12 -inkey lc_key.pem -in lc_cert.pem -password pass:"$PASS" -name "LabCapture Dev"
security create-keychain -p "$PASS" labcapture-sign.keychain
security set-keychain-settings labcapture-sign.keychain   # 자동 잠금 해제
security unlock-keychain -p "$PASS" labcapture-sign.keychain
security import lc.p12 -k labcapture-sign.keychain -P "$PASS" -T /usr/bin/codesign
security set-key-partition-list -S "apple-tool:,apple:,codesign:" -s -k "$PASS" labcapture-sign.keychain
security list-keychains -d user -s login.keychain "$HOME/Library/Keychains/labcapture-sign.keychain-db"
security add-trusted-cert -r trustRoot -p codeSign -k "$HOME/Library/Keychains/login.keychain-db" lc_cert.pem  # GUI 암호 입력 1회
rm -f lc_key.pem lc.p12 lc_cert.pem
```

주의: `-legacy` 필수 (OpenSSL 3의 기본 p12 형식은 macOS Security가 못 읽음 — "MAC verification failed").
인증서를 새로 만들면 지문이 바뀌므로 화면 기록 권한을 다시 한 번만 허용해야 한다.

## 저장 구조

```
~/LabCapture/
  2026-06-11/
    143012_screen.gif
    143012_face.gif
    143012_combo.gif
    143012_screen.mp4      ← "원본 mp4 보존" ON일 때만
    manifest.jsonl         ← 캡처 1건당 1줄: {ts, files[], duration, trigger}
  labcapture.log           ← 에러 로그
```

`trigger` 값: `timer`(주기) / `manual`(메뉴) / `hotkey`(단축키) / `push`(git push 연동)

## 사용법

- **자동**: 기본 20분마다 캡처 (설정에서 5~120분 조절)
- **메뉴바**: 지금 캡처 / 일시정지(1시간·오늘 하루) / 마지막 캡처 보기 / 오늘 폴더 열기 / 설정
- **전역 단축키**: 기본 `⌃⌥⌘C` (설정에서 변경 — 버튼 클릭 후 원하는 키 조합 입력)
- **일시정지 스케줄**: 예: 21:00~09:00 타이머 캡처 자동 중단 (수동 캡처는 가능)
- 잠자기/화면 잠금 중에는 타이머 캡처가 자동 skip
- 디스크 여유 공간 500MB 미만이면 캡처 skip + 알림

## HTTP API (사람 + LLM/봇 공용)

앱이 `http://127.0.0.1:48620` 에서 JSON API를 listen한다 (루프백 전용 — 외부 노출 없음).
**LLM 에이전트는 `GET /capabilities` 하나만 호출하면 전체 API를 자가 발견할 수 있다.**

| 메서드 | 경로 | 동작 |
|---|---|---|
| GET | `/capabilities` | 머신리더블 API 명세 (이 표의 JSON 버전) |
| GET | `/status` | 상태 JSON: `state`(active/paused/capturing/warning), `sources.{screen,face}`, `next_capture_at`, `last_error`, `last_capture_file` |
| POST | `/capture` | 즉시 캡처 (202; 캡처 중이면 409). `GET/POST /trigger`도 동일 (git hook용) |
| POST | `/source/screen/on` · `/off` | 화면 소스 켜기/끄기 |
| POST | `/source/face/on` · `/off` | 얼굴(웹캠) 소스 켜기/끄기 |
| POST | `/pause` · `/pause/today` · `/resume` | 1시간 일시정지 / 오늘 하루 / 재개 |
| POST | `/last/copy` | 마지막 combo.gif를 클립보드에 복사 (X 작성창에 ⌘V) |
| POST | `/timelapse` | 오늘 원본 mp4들을 고화질 1080p 타임랩스로 컴파일 — 화면 배경 + 얼굴 원형 중앙 오버레이, `timelapse_YYYY-MM-DD_HHmmss.mp4` (202) |
| POST | `/summary` | Claude API로 오늘 빌딩 일지(summary.md) 생성 (202; 키 없으면 400) |

상태 변경 요청은 모두 변경 후의 `/status` JSON을 돌려준다.

```bash
curl -s http://127.0.0.1:48620/status | jq .sources
curl -s -X POST http://127.0.0.1:48620/source/face/off   # 얼굴 끄고 화면만 캡처
curl -s -X POST http://127.0.0.1:48620/capture
```

## git push 연동

```bash
curl http://127.0.0.1:48620/trigger   # → 캡처 발동
```

git에는 네이티브 `post-push` 훅이 없으므로 두 가지 방법 중 하나를 쓴다.

**방법 1 — `pre-push` 훅** (푸시 직전 발동, 가장 간단):

```bash
# <your-repo>/.git/hooks/pre-push  (chmod +x 필수)
#!/bin/sh
curl -s -m 2 http://127.0.0.1:48620/trigger >/dev/null 2>&1 || true
exit 0
```

```bash
chmod +x <your-repo>/.git/hooks/pre-push
```

**방법 2 — git alias** (푸시 성공 직후 발동):

```bash
git config --global alias.pushc '!git push "$@" && curl -s -m 2 http://127.0.0.1:48620/trigger >/dev/null; true'
# 이후 git pushc 로 푸시
```

## 설정 항목

| 항목 | 기본값 | 범위 |
|---|---|---|
| 캡처 주기 | 20분 | 5~120 |
| 캡처 길이 | 3초 | 1~5 |
| 사전 알림 / 리드타임 | ON / 3초 | 0~10초 |
| 웹캠 캡처 | ON | OFF 시 screen.gif만 생성 |
| PiP 위치 | 우하단 | 좌상/우상/좌하/우하 |
| GIF fps | 15 | 8~15 |
| 화면 GIF 가로폭 | 960px | 480~1080 |
| 출력 폴더 | ~/LabCapture | 변경 가능 |
| 원본 mp4 보존 | ON | 고화질 타임랩스 재료 — 끄면 타임랩스가 GIF 폴백(저화질) |
| 일시정지 스케줄 | OFF | 시작/종료 시각 |
| 전역 단축키 | ⌃⌥⌘C | 변경 가능 |

모든 설정은 `UserDefaults`에 저장되어 재실행 시 유지된다.

## 민감정보 가드 (OCR) — v0.2

화면 녹화 직후 Vision OCR로 프레임을 스캔해 API 키·토큰·비밀번호·DB 접속 문자열 패턴이 보이면 **캡처를 통째로 폐기**한다 (부분 블러는 프레임 추적 누락 시 유출 위험이 있어 채택하지 않음).

폐기 정책:
1. 감지 → 폐기 → **즉시 재캡처** (알림으로 안내)
2. **연속 3회** 폐기되면 → 캡처 자동 중단 (기본 2시간, 설정 1~12시간)
3. 중단 시간이 지나면 자동 재개. 화면 정리 후 메뉴 "재개"로 즉시 해제도 가능

감지 패턴: `sk-...`(Anthropic/OpenAI), GitHub 토큰/PAT, AWS 키, Slack/Notion 토큰, JWT, PRIVATE KEY 블록, Bearer 토큰, DB 접속 문자열, `API_KEY=...` 류 환경변수 할당. OCR 오인식(`-`→`=` 등)을 감안해 느슨하게 매칭한다 — 가드는 과잉 감지가 안전하다.

설정에서 끌 수 있다 ("민감정보 가드" 토글). 디버그: `LabCapture --ocr-test <video.mp4>`.

## 일일 파이프라인 — v0.3

메뉴 "오늘 정리" 또는 HTTP API:

- **타임랩스 (v0.4 고화질)**: 오늘 폴더의 원본 mp4들을 시간순으로 이어붙여 1080p/30fps/crf18 mp4 생성 — 화면이 배경 그대로, 얼굴은 **원형으로 화면 중앙**에 오버레이, 구간별 캡처 시각 표시. 파일명 `timelapse_YYYY-MM-DD_HHmmss.mp4`. 원본 mp4가 없는 구버전 폴더는 GIF concat 폴백
- **빌딩 일지 (Claude)**: manifest.jsonl + combo 캡처 대표 프레임(최대 6장)을 Claude API(`claude-opus-4-8`)에 보내 `summary.md` 생성 — 한 줄 요약 / 타임라인 / X 콘텐츠 소재 추천
- **X 업로드 헬퍼**: 메뉴 "마지막 캡처 클립보드 복사" 또는 `POST /last/copy` → X 작성창에 ⌘V

Claude API 키 설정 (하드코딩 금지 — 파일 또는 환경변수):

```bash
mkdir -p ~/.config/labcapture && printf '%s' 'sk-ant-...' > ~/.config/labcapture/anthropic_api_key && chmod 600 ~/.config/labcapture/anthropic_api_key
```

## 소스 토글 (화면/얼굴 개별 ON/OFF)

메뉴바 메뉴의 "화면 캡처" / "얼굴 캡처" 토글 또는 HTTP API로 소스를 개별로 끌 수 있다.

- 화면만 ON → `screen.gif`만 생성
- 얼굴만 ON → `face.gif`만 생성
- 둘 다 ON → 3종 모두 (combo는 둘 다 켜졌을 때만)
- 둘 다 OFF → 타이머 캡처 조용히 skip (수동 캡처 시도 시 안내 알림)

## 메뉴바 아이콘

아이콘은 두 도형: **사각형=화면 소스, 원=얼굴 소스**. 채워짐=ON, 윤곽선+슬래시=OFF.
색이 전체 상태를 나타낸다:

- 🟢 라임 — 활성
- ⚪ 회색 — 일시정지
- 🔴 빨강 — 캡처 중
- 🟠 주황 — 마지막 캡처 실패 (메뉴에서 에러 로그 확인 시 해제)

## manifest.jsonl 스키마 (LLM 파이프라인 입력)

캡처 1건당 1줄, `schema: 1`:

```json
{"schema":1,"ts":"2026-06-11T18:25:23+09:00","trigger":"push","duration":2,
 "sources":["screen","face"],
 "files":["182523_screen.gif","182523_face.gif","182523_combo.gif"],
 "kinds":{"182523_screen.gif":"screen","182523_face.gif":"face","182523_combo.gif":"combo"}}
```

## 아키텍처

Swift/SwiftUI 메뉴바 앱이 오케스트레이터, 실제 녹화·인코딩은 ffmpeg 서브프로세스에 위임.

```
Sources/LabCapture/
  LabCaptureApp.swift    앱 엔트리 (MenuBarExtra + Settings scene)
  AppModel.swift         중앙 상태: 타이머/일시정지/잠금감지/에러로그/온보딩
  CaptureEngine.swift    녹화 → GIF 3종 변환 → manifest (핵심 파이프라인)
  FFmpeg.swift           ffmpeg 프로세스 러너 + avfoundation 장치 탐지
  TriggerServer.swift    127.0.0.1:48620 HTTP 트리거 (git push 연동)
  HotkeyManager.swift    Carbon 전역 단축키
  Notifier.swift         macOS 알림
  Permissions.swift      TCC 권한 체크/요청/설정 패널 열기
  Views/                 메뉴/설정/온보딩 UI
```

GIF 인코딩: ffmpeg 2-pass 팔레트 (`palettegen` → `paletteuse`, bayer 디더링), 무한 루프.
타임스탬프 오버레이: `drawtext` + `textfile=` (필터그래프 콜론 이스케이프 회피).

## v0.1 범위 외

~~PiP 원형 마스크~~·~~고화질 타임랩스~~(v0.4 완료), 공증/서명·ffmpeg 번들링, 다중 모니터 선택(메인 디스플레이 고정).
