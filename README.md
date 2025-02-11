# Signal message bus

![Language](https://img.shields.io/badge/language-C99-blue?logo=c&logoColor=white)
![Platform](https://img.shields.io/badge/platform-POSIX-lightgrey)

`signal_message_bus`는 42 `minitalk` 과제를 변형한 C 프로젝트입니다. UNIX signal로 별도 프로세스 사이에 문자열을 전달하고, UNIX domain socket 기반 응답 채널로 세션 소유권과 각 비트의 전달 결과를 확인합니다.

## 구성

- `build/bin/server`: 수신 서버를 시작하고 자신의 PID를 표준 출력에 기록합니다.
- `build/bin/client`: 서버 PID와 메시지를 받아 서버로 한 줄을 전송합니다.
- 서버는 메시지의 NUL 종료를 줄바꿈으로 출력합니다.
- 한 세션에 하나의 client만 연결할 수 있으며, 사용 중인 서버는 다른 client를 거부합니다.
- 오래된 socket 파일, 잘못된 PID, signal 전달 시간 초과를 검사합니다.

## 빌드

저장소 루트에서 실행합니다.

```sh
make
```

일반 실행 파일은 `build/bin/`, 테스트 실행 파일은 `build/test/`, 중간 오브젝트와 의존성 파일은 `build/obj/`에 생성됩니다. fault injection 테스트용 오브젝트는 `build/fault/`에 생성됩니다.

## 사용 예시

터미널 1에서 서버를 시작합니다.

```sh
./build/bin/server
```

출력된 PID를 터미널 2에서 사용합니다.

```sh
./build/bin/client <server_pid> "hello, signal bus"
```

서버는 다음과 같이 메시지를 출력합니다.

```text
hello, signal bus
```

client는 인자를 정확히 두 개 받아야 하며, 서버가 없거나 응답이 시간 초과되면 표준 오류에 원인을 기록하고 실패합니다.

## 테스트

```sh
make test
```

다음 범위를 포함한 테스트를 실행합니다.

- PID 파싱과 기본 송수신
- 여러 client의 세션 소유권
- 응답 source와 protocol 검증
- 출력 실패와 부분 쓰기
- stale socket과 signal mask 처리
- 높은 파일 디스크립터 환경

## 정리

```sh
make clean  # build/ 중간 산출물 삭제
make fclean # clean 후 실행 파일과 테스트 실행 파일 삭제
make re     # fclean 후 전체 재빌드
```

프로젝트의 실행 파일과 테스트 실행 파일은 저장소에 포함하지 않습니다.
