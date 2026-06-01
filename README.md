# CCUsageWidget — macOS Desktop Widget (Floating Panel)

Claude Code의 현재 사용량(5시간·7일 윈도우)과 플랜 상태를 **macOS 바탕화면에 떠 있는 위젯 스타일 패널**로 보여줍니다.

> ⚠️ `/api/oauth/usage`는 Anthropic의 **비공식 내부 엔드포인트**입니다. 언제 변경될 수 있으니 참고용으로만 사용하세요.

## 기능

- **5시간** / **7일** 사용률 게이지
- **Sonnet / Opus** 모델별 7일 사용량
- 다음 리셋 시간 표시
- Extra Credits 상태
- 60초마다 자동 새로고침
- 위젯 스타일 디자인 (둥근 모서리 + 그림자 + 투명 배경)
- 항상 위에 떠 있음 (어떤 Space에서도 보임)

## 요구사항

- macOS 14 (Sonoma) 이상
- Claude Code OAuth 로그인 상태 (`claude auth login`)
- Xcode Command Line Tools (`swift` 명령)

## 빌드 & 실행

```bash
cd cc-usage-widget
swift build

# 실행
.build/debug/cc-usage-widget
```

## 사용법

### 화면 배치
- 실행하면 화면 **우측 상단**에 패널이 나타납니다.
- 드래그로 원하는 위치로 이동할 수 있습니다.
- **Close 버튼**은 숨겨져 있으며, 패널을 **우클릭**하면 컨텍스트 메뉴에서 종료할 수 있습니다.

### 종료
- 패널 **우클릭** → 컨텍스트 메뉴에서 종료
- 또는 터미널에서 `killall cc-usage-widget`

## 프로젝트 구조

```
cc-usage-widget/
├── Package.swift                        # Swift Package
├── Sources/CCUsageWidget/main.swift     # Floating Panel + SwiftUI
└── README.md
```

## 인증 방식

- macOS Keychain의 `"Claude Code-credentials"` 항목에서 OAuth `accessToken` 읽기
- → `/api/oauth/usage` 호출

`claude auth login`이 되어 있지 않으면 **"로그인 필요"** 메시지가 표시됩니다.

## 주의

- 위젯이 항상 위에 떠 있으므로 작업 공간을 가릴 수 있습니다 — 원하는 위치로 드래그해서 배치하세요.
- 코드 서명 없이 실행 가능합니다 (Ad-hoc).
