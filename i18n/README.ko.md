# LaunchNG

**언어**: [English](../README.md) | [简体中文](README.zh.md) | [繁體中文](README.zh-TW.md) | [日本語](README.ja.md) | [한국어](README.ko.md) | [Français](README.fr.md) | [Español](README.es.md) | [Deutsch](README.de.md) | [Русский](README.ru.md) | [हिन्दी](README.hi.md) | [Tiếng Việt](README.vi.md) | [Italiano](README.it.md) | [Čeština](README.cs.md)

macOS Tahoe(26)는 Launchpad를 완전히 없애버렸습니다. LaunchNG는 이를 네이티브 앱으로 되살립니다. 첫 실행 시 macOS 자체 데이터베이스에서 기존 Launchpad 레이아웃을 그대로 읽어온 뒤, Core Animation으로 렌더링되는 그리드 위에 페이지 넘김, 폴더, 검색, 드래그 앤 드롭 재정렬을 직접 구현합니다. Dock 연동, 번들된 CLI/TUI, 서명된 앱 내 자동 업데이트까지 포함합니다.

## 다운로드

**[최신 릴리스 받기](https://github.com/moonmig/LaunchNG/releases/latest)**

유용하게 사용하고 계신다면 저장소에 star를 눌러주시면 큰 힘이 됩니다. LaunchNG는 RoversX의 [LaunchNext](https://github.com/RoversX/LaunchNext)에서 포크되어 시작된 프로젝트입니다 — 원본 프로젝트에도 star 부탁드립니다.

<!-- 스크린샷은 여기에 들어갑니다. 최신 스크린샷을 제공해주실 수 있다면 "기여하기" 섹션을 참고해주세요. -->

### macOS가 앱 실행을 막을 때

이 포크의 릴리스는 서명되지 않은/ad-hoc 빌드입니다(이 프로젝트는 유료 Apple Developer 계정을 사용하지 않습니다). 따라서 Gatekeeper는 격리 플래그를 한 번 해제하기 전까지 앱 실행을 거부합니다:

```bash
sudo xattr -r -d com.apple.quarantine /Applications/LaunchNG.app
```

이 명령어는 신뢰하는 앱에 대해서만 실행하세요 — 해당 앱에 대한 macOS의 다운로드 격리 검사를 비활성화합니다.

소스에서 직접 빌드하시나요? 이 명령어는 필요 없습니다. 아래 [로컬 코드 서명 설정](#configure-local-code-signing)을 참고하세요.

## LaunchNG가 제공하는 것

- **실제 Launchpad 데이터베이스에서 원클릭 가져오기** —— `/private$(getconf DARWIN_USER_DIR)com.apple.dock.launchpad/db/db`를 직접 읽어 기존 폴더, 위치, 페이지를 그대로 복원
- **클래식한 페이지 그리드 경험** —— 검색, 키보드 탐색, 드래그 앤 드롭 재정렬, 아이콘을 다른 아이콘 위로 드래그해 폴더 생성
- **전 과정 Core Animation 렌더링**, Dock으로 바로 드래그하는 기능과 macOS 26의 네이티브 Liquid Glass 폴더 아이콘 포함
- **폴더 레이아웃**: 원본과 같은 페이지 방식 또는 세로 스크롤 방식 중 선택 가능
- **퍼지 검색**, CJK(병음 등) 변환 매칭 지원으로 입력이 정확하지 않거나 일부만 입력해도 원하는 앱을 찾음
- **핫 코너 및 트랙패드 제스처 실행**, 실험적인 4/5손가락 핀치·탭 지원 포함
- **CLI와 TUI**로 터미널에서 레이아웃을 확인하고 조작 가능
- **[Sparkle](https://sparkle-project.org) 기반 서명된 자동 업데이트**, 앱 내 일반적인 "업데이트 확인" 버튼 제공
- **원하는 폴더로의 로컬 백업**, 복원 가능한 이력까지 관리
- **앱 아이콘 라벨 숨기기, 아이콘 크기·간격 조절** —— 메인 그리드와 폴더 내부를 각각 독립적으로 설정 가능
- **13개 언어**의 완전한 UI 번역(위 언어 목록 참고)
- **강화된 컨텍스트 메뉴** —— Finder에서 보기, 앱 경로 복사, 폴더 이름 변경, 그리고 (선택 사항) 신뢰하는 다른 앱의 Gatekeeper 격리를 해제하는 단축 기능
- **컨트롤러 및 음성 피드백 지원**으로 접근성 고려

## macOS Tahoe가 빼앗아간 것들

- 사용자 지정 폴더나 자유로운 구성 불가
- 드래그 앤 드롭 재정렬 불가
- 시각적인 앱 관리 자체가 전무함 —— 자동 생성되어 알파벳순으로 정렬된, 손댈 수 없는 그리드뿐

LaunchNG가 존재하는 이유는 이것이 합리적인 기본값이 아니라 명백한 퇴보이기 때문입니다.

## 데이터 저장 위치

LaunchNG 자체 레이아웃, 환경설정, 캐시는 다음 위치에 저장됩니다:

```
~/Library/Application Support/LaunchNG/Data.store
```

어디로도 데이터를 전송하지 않습니다. 유일한 네트워크 활동은 업데이트 피드 확인과, 사용자가 직접 실행할 경우에 한해 Apple 자체 Launchpad 데이터베이스를 읽는 것입니다:

```bash
/private$(getconf DARWIN_USER_DIR)com.apple.dock.launchpad/db/db
```

## 설치

### 요구 사항

- macOS 26(Tahoe) 이상
- Apple Silicon 또는 Intel
- 소스에서 빌드할 경우 Xcode 26

### 소스에서 빌드

```bash
git clone https://github.com/moonmig/LaunchNG.git
cd LaunchNG
open LaunchNG.xcodeproj
```

<a name="configure-local-code-signing"></a>**로컬 코드 서명 설정** (유료 Apple Developer 계정 불필요):

- **LaunchNG** 타겟 선택 → **Signing & Capabilities** → **Team**을 `None`으로, 서명 인증서를 `Sign to Run Locally`로 설정. Hardened Runtime은 켜진 상태로 둡니다.
- 이후 Xcode가 프로젝트 파일을 변경됨으로 표시합니다 —— 서명 관련 변경 사항만 pull request에 포함하지 마세요.

`⌘R`로 실행하려면 대상이 **My Mac**이어야 합니다 —— 유니버설/"Any Mac" 대상은 빌드와 아카이브는 가능하지만 디버깅 실행은 불가능합니다. 빌드만 할 때는 `⌘B`.

### 커맨드라인 빌드

```bash
xcodebuild -project LaunchNG.xcodeproj -scheme LaunchNG -configuration Release

# 유니버설 바이너리 (Apple Silicon + Intel):
xcodebuild -project LaunchNG.xcodeproj -scheme LaunchNG -configuration Release \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO clean build
```

## 사용법

1. **첫 실행 시** 설치된 애플리케이션을 자동으로 스캔합니다.
2. **설정 → General → Import System Launchpad**로 기존 레이아웃, 폴더, 위치를 한 번에 가져옵니다.
3. 클릭으로 선택, 더블클릭(또는 Return)으로 실행; 아무 곳에서나 입력하면 바로 검색됩니다.
4. 한 앱을 다른 앱 위로 드래그해 폴더 생성; 앱을 드래그해 순서 변경.
5. 터미널에서 레이아웃을 스크립트로 다루고 싶다면 설정에서 CLI를 활성화하세요.

### 전체화면 vs. 컴팩트

- **전체화면**은 화면 전체를 채우며 원본 Launchpad에 가장 가깝습니다.
- **컴팩트**는 크기 조절이 가능한 둥근 모서리의 플로팅 창입니다.
- 외관 설정(아이콘 배율, 간격, 페이지 인디케이터 위치 등)은 모드별로 별도로 저장됩니다.
- 전체화면에서는 메뉴 막대를 선택적으로 숨길 수 있으며, 이때 Dock도 macOS가 자동으로 숨깁니다.

## 주요 설정 항목

- **외관**: 아이콘 배율, 라벨 크기와 표시 여부, 그리드 간격 —— 폴더 내부는 별도 값 설정 가능 —— 그리고 배경 스타일(블러, 네이티브 Liquid Glass, 또는 실시간 배경화면 기반 배경)
- **검색**: 퍼지 매칭 토글과 검색 디바운스 시간
- **숨긴 앱**: 삭제하지 않고 특정 앱을 그리드에서 숨김
- **백업**: 폴더 선택, 타임스탬프가 찍힌 백업 생성, 목록에서 복원 또는 삭제
- **단축키 및 제스처**: 전역 단축키, 핫 코너, (실험적인) 트랙패드 제스처 바인딩
- **업데이트**: 자동 확인 토글과 수동 "업데이트 확인" 버튼, 모두 Sparkle 기반

## 문제 해결

**앱이 시작되지 않아요.** macOS 26.0 이상인지, 격리 플래그가 해제되었는지 확인하세요(위 참고).

**"업데이트 확인"에서 오류가 나요.** LaunchNG는 서명된 업데이트 피드를 사용하는 Sparkle을 사용합니다. 수동 확인은 몇 분 내에 최신 릴리스를 항상 정확히 반영해야 합니다.

**터미널에 `launchng` 명령어가 없어요.** 이건 선택 사항입니다 —— 먼저 설정에서 커맨드라인 인터페이스를 활성화하세요. LaunchNG가 관리되는 명령어를 직접 설치하며(나중에 제거도 가능), 필요할 때 알아서 처리합니다.

## 기여하기

1. 저장소를 fork
2. 기능 브랜치 생성 (`git checkout -b feature/your-feature`)
3. 명확한 메시지로 커밋
4. 브랜치 push 후 pull request 열기

리뷰가 순조롭게 진행되도록 도와주는 팁:
- 서명 관련 Xcode 프로젝트 변경 사항은 diff에서 제외하세요 (위 로컬 코드 서명 참고)
- Core Animation 그리드를 수정한다면 먼저 `GridReorderPlan.swift`를 확인하세요 —— 재정렬/페이징 로직은 여기에 모아야 하며 뷰마다 중복 구현하지 마세요
- PR을 열기 전에 테스트 스위트를 실행하세요:
  ```bash
  xcodebuild test -scheme LaunchNG -destination 'platform=macOS'
  ```

최신의 정확한 스크린샷(메인 그리드, 설정 탭 몇 개)을 제공해주시는 것도 정말 값진 기여입니다 —— 이 파일 상단의 플레이스홀더를 참고하세요.

### 추가 문서

- [Folder Liquid Glass](../Documentation/FolderLiquidGlass.md) —— 폴더 유리 아이콘 뒤에 숨은 디자인 제약, 검증된 부분, 그리고 아직 승인 테스트가 필요한 부분
- [Grid diagnostics](../scripts/diagnostics/README.md) —— 그리드와 유리 오버레이용 수동 진단 도구와 그 정확한 커버리지 및 한계

## 라이선스와 크레딧

LaunchNG는 RoversX의 [LaunchNext](https://github.com/RoversX/LaunchNext)에서 포크된 프로젝트이며, 이는 다시 더 넓은 Launchpad 대체 커뮤니티 프로젝트로 거슬러 올라갑니다. 두 프로젝트 모두 GPL-3.0으로 라이선스되어 있으며, LaunchNG도 동일한 조건을 따릅니다 —— [LICENSE](../LICENSE) 참고.

실험적인 트랙패드 제스처 지원은 [OpenMultitouchSupport](https://github.com/Kyome22/OpenMultitouchSupport)와 [KrishKrosh](https://github.com/KrishKrosh/OpenMultitouchSupport)의 포크를 기반으로 합니다.

---

![GitHub downloads](https://img.shields.io/github/downloads/moonmig/LaunchNG/total)
