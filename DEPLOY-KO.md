# 모아 온라인 대시보드 설정

이 폴더는 Vercel에서 정적 사이트로 제공하고 Supabase에서 이메일 로그인과 계정별 데이터를 저장하도록 준비되어 있습니다. 데이터베이스 정책은 로그인한 사용자가 자기 워크스페이스 행만 읽고 쓸 수 있게 제한합니다.

## 1. Supabase 프로젝트 만들기

1. Supabase에서 새 프로젝트를 만듭니다.
2. SQL Editor에서 supabase-schema.sql 내용을 실행합니다.
3. Project Settings → API에서 Project URL과 Publishable key를 확인합니다.
4. supabase-config.js에 두 값을 넣습니다. 브라우저용 Publishable key만 사용하세요. service_role 키는 넣지 마세요.

## 2. Vercel에 배포하기

1. 이 폴더의 파일을 GitHub 저장소 루트에 올립니다. `api/exchange-rates.js`도 그대로 포함해야 네이버 매매기준율을 안정적으로 불러옵니다.
2. Vercel에서 저장소를 가져옵니다. 빌드 명령은 비워 두고 Output Directory는 기본값으로 둡니다. Vercel이 `api/`의 환율 조회 함수를 자동으로 배포합니다.
3. 배포가 끝나면 Vercel이 발급한 https://...vercel.app 주소가 로그인 페이지 주소가 됩니다.

## 3. 로그인 주소 등록하기

Supabase → Authentication → URL Configuration에서 Site URL을 Vercel 주소로 설정하고, Redirect URLs에도 같은 주소를 추가합니다. 이메일 확인 링크가 배포 사이트로 돌아오도록 이 설정이 필요합니다.

이메일 확인이 켜져 있으면 계정 생성 후 이메일 링크를 누른 다음 로그인하세요. 여러 컴퓨터에서 같은 계정으로 로그인하면 저장된 사업과 거래가 불러와집니다.

## 현재 준비 상태

Supabase 프로젝트와 Vercel 계정이 이 작업 공간에 연결되어 있지 않아 공개 주소는 아직 발급되지 않았습니다. 계정을 만든 뒤 Project URL, Publishable key, 배포된 Vercel 주소를 설정하면 온라인 사용을 시작할 수 있습니다.

현재 구현은 한 계정이 여러 기기에서 사용하는 방식입니다. 여러 사람이 각자 다른 계정으로 같은 워크스페이스를 공동 관리하려면 멤버 초대 기능을 추가해야 합니다.
