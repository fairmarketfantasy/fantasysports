# namespace :seed do
#   task :nfl_data do
#     root = File.join(Rails.root, '..', 'datafetcher')
#     `GOPATH=#{root} go run #{root}/datafetcher.go -year 2013 -fetch serve`
#   end
# end


def run_fetcher(args)
  root = File.join(Rails.root, '..', 'datafetcher')
  `PATH=$PATH:/usr/local/go/bin GOPATH=#{root} go run #{root}/src/github.com/MustWin/datafetcher/datafetcher.go #{args}`
end

namespace :seed do
  task :reload do
    `rake db:drop`
    `rake db:create`
    # IF YOU WANT TO RECREATE THIS FILE, DO IT LIKE THIS:
    # 1) create a fresh db
    # 2) run migrations
    # 3) run the datafetcher for whatever things you need: markets, game play by plays, multiple sports, whatever
    # 4) DUMP THE SQL BEFORE TENDING MARKETS. KTHX.
    ActiveRecord::Base.load_sql_file File.join(Rails.root, 'db', 'reload.sql')
    `rake db:migrate`
    `rake db:setup_functions`
    `rake deploy:create_oauth_client`
    `rake seed:tend_markets_once`
  end

  task :tend_markets_once => :environment do
    Market.tend_all
  end

  namespace :nfl do

    task :data do
      #ensure that another datafetcher task is not running
      run_fetcher "-year 2013 -fetch serve"
    end

    task :market, [:market_id] =>  :environment do |t, args|
      raise "Must pass market_id" if args.market_id.nil?
      market = Market.find(Integer(args.market_id))
      market.games.each do |game|
        run_fetcher "-fetch stats -year 2013 -season #{game.season_type} -week #{game.season_week} -home #{game.home_team} -away #{game.away_team}"
      end
      market.tabulate_scores
    end
  end

  task :push_headshots_to_s3 => :environment do
    # Fetch the headshot
    headshot_manifest = "http://api.sportsdatallc.org/nfl-images-p1/manifests/headshot/all_assets.xml?api_key=yq9uk9qu774eygre2vg2jafe"
    path = File.join(Rails.root, '..', 'docs', 'sportsdata', 'nfl', 'headshots.xml')
=begin
    open(headshot_manifest) do |xml|
      File.open(path, 'w') do |f|
        f.write(xml.read)
      end
    end
=end
uploaded = %w(
23c9e491-bf62-48e2-abc3-057b50dc1142/195.jpg
23c9e491-bf62-48e2-abc3-057b50dc1142/65.jpg
b32c3a32-6888-482f-b488-19665fa2dee3/195.jpg
b32c3a32-6888-482f-b488-19665fa2dee3/65.jpg
905bed9e-13e7-4967-bf69-8764c7df19af/195.jpg
905bed9e-13e7-4967-bf69-8764c7df19af/65.jpg
37a416e3-e266-4807-9e02-e4cc18cfa41e/195.jpg
37a416e3-e266-4807-9e02-e4cc18cfa41e/65.jpg
6d9a19b5-f525-4ea8-b5e0-ab715387ee14/195.jpg
6d9a19b5-f525-4ea8-b5e0-ab715387ee14/65.jpg
19244cf5-642d-4a17-9542-8868ba8ce108/195.jpg
19244cf5-642d-4a17-9542-8868ba8ce108/65.jpg
95dd80d2-78e3-47ea-bab4-9f1cc1cb6163/195.jpg
95dd80d2-78e3-47ea-bab4-9f1cc1cb6163/65.jpg
a969045b-9e00-4ea7-99c9-f2dd54c0870e/195.jpg
a969045b-9e00-4ea7-99c9-f2dd54c0870e/65.jpg
074813a8-7a39-425a-bacb-36f03c243d6d/195.jpg
074813a8-7a39-425a-bacb-36f03c243d6d/65.jpg
47854a41-5929-481c-bb67-1c05b1e23047/195.jpg
47854a41-5929-481c-bb67-1c05b1e23047/65.jpg
4b141894-2d9d-493b-a3ea-1578a79d0a49/195.jpg
4b141894-2d9d-493b-a3ea-1578a79d0a49/65.jpg
71d01906-59c5-487e-9f42-1b060e5baba3/195.jpg
71d01906-59c5-487e-9f42-1b060e5baba3/65.jpg
be29c1a1-7db6-4534-a42e-40987ec3b2da/195.jpg
be29c1a1-7db6-4534-a42e-40987ec3b2da/65.jpg
d02e088a-575d-4214-8125-577c10c2f813/195.jpg
d02e088a-575d-4214-8125-577c10c2f813/65.jpg
cb78b71a-a954-4d5d-88b9-25d1126e09b9/195.jpg
cb78b71a-a954-4d5d-88b9-25d1126e09b9/65.jpg
0ec32e87-12e0-4779-a6ad-8aa4c5569e01/195.jpg
0ec32e87-12e0-4779-a6ad-8aa4c5569e01/65.jpg
91797552-9015-4a20-a201-2453a5ab24c0/195.jpg
91797552-9015-4a20-a201-2453a5ab24c0/65.jpg
b086fe93-0bfd-44b6-8ad1-3082233e4839/195.jpg
b086fe93-0bfd-44b6-8ad1-3082233e4839/65.jpg
177a9982-a7fd-488e-a2f1-8c814892ce2e/195.jpg
177a9982-a7fd-488e-a2f1-8c814892ce2e/65.jpg
913bbabe-e8e1-4867-b698-f01bdd86bdf8/195.jpg
913bbabe-e8e1-4867-b698-f01bdd86bdf8/65.jpg
71d01906-59c5-487e-9f42-1b060e5baba3/195.jpg
71d01906-59c5-487e-9f42-1b060e5baba3/65.jpg
be29c1a1-7db6-4534-a42e-40987ec3b2da/195.jpg
be29c1a1-7db6-4534-a42e-40987ec3b2da/65.jpg
d02e088a-575d-4214-8125-577c10c2f813/195.jpg
d02e088a-575d-4214-8125-577c10c2f813/65.jpg
cb78b71a-a954-4d5d-88b9-25d1126e09b9/195.jpg
cb78b71a-a954-4d5d-88b9-25d1126e09b9/65.jpg
0ec32e87-12e0-4779-a6ad-8aa4c5569e01/195.jpg
0ec32e87-12e0-4779-a6ad-8aa4c5569e01/65.jpg
91797552-9015-4a20-a201-2453a5ab24c0/195.jpg
91797552-9015-4a20-a201-2453a5ab24c0/65.jpg
b086fe93-0bfd-44b6-8ad1-3082233e4839/195.jpg
b086fe93-0bfd-44b6-8ad1-3082233e4839/65.jpg
177a9982-a7fd-488e-a2f1-8c814892ce2e/195.jpg
177a9982-a7fd-488e-a2f1-8c814892ce2e/65.jpg
913bbabe-e8e1-4867-b698-f01bdd86bdf8/195.jpg
913bbabe-e8e1-4867-b698-f01bdd86bdf8/65.jpg
452b9abe-b339-4f61-8ce6-d760c5c856a6/195.jpg
740f0409-d1aa-41e8-b637-de744ecb1f8d/195.jpg
740f0409-d1aa-41e8-b637-de744ecb1f8d/65.jpg
452b9abe-b339-4f61-8ce6-d760c5c856a6/65.jpg
3b064c78-492f-4efb-994a-a33030131192/195.jpg
3b064c78-492f-4efb-994a-a33030131192/65.jpg
2771dada-5702-46da-b0d5-9cbe416c2a5c/195.jpg
2771dada-5702-46da-b0d5-9cbe416c2a5c/65.jpg
14591969-0330-4be1-9150-625952e18b7b/195.jpg
14591969-0330-4be1-9150-625952e18b7b/65.jpg
db5159fe-8ad2-4888-ad1a-58ff8ad99029/195.jpg
db5159fe-8ad2-4888-ad1a-58ff8ad99029/65.jpg
4e54c7eb-4f81-4d7d-b652-544fa2fb4c6c/195.jpg
4e54c7eb-4f81-4d7d-b652-544fa2fb4c6c/65.jpg
0c9c1429-ef35-450a-8386-7f001024b0e2/195.jpg
0c9c1429-ef35-450a-8386-7f001024b0e2/65.jpg
1968234a-9669-4bc3-8189-e0216446c080/195.jpg
1968234a-9669-4bc3-8189-e0216446c080/65.jpg
4967377c-9009-4e77-8b8d-933f9b40e526/195.jpg
4967377c-9009-4e77-8b8d-933f9b40e526/65.jpg
185b4f1a-7277-4f4e-a42a-9487dd965940/195.jpg
185b4f1a-7277-4f4e-a42a-9487dd965940/65.jpg
a0352ca6-dc1f-420d-b04b-c1b393bc3e5f/195.jpg
a0352ca6-dc1f-420d-b04b-c1b393bc3e5f/65.jpg
9f8d3a12-4e35-44de-9691-9da2783a5440/195.jpg
9f8d3a12-4e35-44de-9691-9da2783a5440/65.jpg
5a42d649-584b-49a0-9a9b-d4079bad1484/195.jpg
5a42d649-584b-49a0-9a9b-d4079bad1484/65.jpg
336ff4f4-dc7e-449d-90c6-fe282a7a6047/195.jpg
336ff4f4-dc7e-449d-90c6-fe282a7a6047/65.jpg
3d73c5b4-7542-4b24-b62e-e408559375aa/195.jpg
3d73c5b4-7542-4b24-b62e-e408559375aa/65.jpg
63a47a38-c478-449a-9dfc-835c25948a26/195.jpg
63a47a38-c478-449a-9dfc-835c25948a26/65.jpg
bbb28c1a-a27f-4c19-ae76-733293a028e1/195.jpg
bbb28c1a-a27f-4c19-ae76-733293a028e1/65.jpg
3b940b54-837c-4b60-9206-055408cba289/195.jpg
3b940b54-837c-4b60-9206-055408cba289/65.jpg
d4384d09-dc09-486e-abc8-a476ea1f59ca/195.jpg
d4384d09-dc09-486e-abc8-a476ea1f59ca/65.jpg
4fe77bc1-dacb-46bd-b553-71d816d06a1c/195.jpg
4fe77bc1-dacb-46bd-b553-71d816d06a1c/65.jpg
7ddf761a-5a35-49df-8bed-fea4f232b15c/195.jpg
7ddf761a-5a35-49df-8bed-fea4f232b15c/65.jpg
1c03c9ea-ea1c-4d3a-836d-61db9b37e7ad/195.jpg
1c03c9ea-ea1c-4d3a-836d-61db9b37e7ad/65.jpg
0a3d0db4-a746-4419-aff4-42da6a41b4c7/195.jpg
0a3d0db4-a746-4419-aff4-42da6a41b4c7/65.jpg
b637dd24-e72d-486f-b144-377fca248bcb/195.jpg
b637dd24-e72d-486f-b144-377fca248bcb/65.jpg
1efc429e-ac70-44d9-bc75-0707f73d3578/195.jpg
1efc429e-ac70-44d9-bc75-0707f73d3578/65.jpg
599cb767-bfad-4ec7-8c7b-f605fc1b74fc/195.jpg
599cb767-bfad-4ec7-8c7b-f605fc1b74fc/65.jpg
dfb9b7d3-0853-4782-9cb2-5a146bbffcb2/195.jpg
dfb9b7d3-0853-4782-9cb2-5a146bbffcb2/65.jpg
e5ebb149-74b0-4164-986d-3f4bef3f4eae/195.jpg
e5ebb149-74b0-4164-986d-3f4bef3f4eae/65.jpg
06f40f02-94f5-45ea-8478-f7a824743302/195.jpg
06f40f02-94f5-45ea-8478-f7a824743302/65.jpg
2b6b4985-d8d1-48ad-8f6c-5a4f01edfda9/195.jpg
2b6b4985-d8d1-48ad-8f6c-5a4f01edfda9/65.jpg
82b70595-cc7a-449c-8620-55e7a8323362/195.jpg
82b70595-cc7a-449c-8620-55e7a8323362/65.jpg
66555024-882f-491c-91f5-496bc08f3838/195.jpg
66555024-882f-491c-91f5-496bc08f3838/65.jpg
08febba2-b5e6-4138-af4f-85ae5680fce9/195.jpg
08febba2-b5e6-4138-af4f-85ae5680fce9/65.jpg
ee14c8b4-7739-4cc7-8e68-2dd14b2abb2a/195.jpg
ee14c8b4-7739-4cc7-8e68-2dd14b2abb2a/65.jpg
53c2b88b-12cd-4164-9d3d-5c4dc8c1b5d9/195.jpg
53c2b88b-12cd-4164-9d3d-5c4dc8c1b5d9/65.jpg
ce3ed318-523c-4098-a1b3-bca3ad486a81/195.jpg
ce3ed318-523c-4098-a1b3-bca3ad486a81/65.jpg
0bbd883b-145b-446e-9c4e-e578af5b817b/195.jpg
0bbd883b-145b-446e-9c4e-e578af5b817b/65.jpg
fa66f1d8-bb35-472b-a57e-8fb8e273e93e/195.jpg
fa66f1d8-bb35-472b-a57e-8fb8e273e93e/65.jpg
4f4aa505-0903-44d4-910b-0c15b61bf1ae/195.jpg
4f4aa505-0903-44d4-910b-0c15b61bf1ae/65.jpg
8ca161ba-495c-487c-99a1-a4fff1640715/195.jpg
8ca161ba-495c-487c-99a1-a4fff1640715/65.jpg
71bf182f-98cc-494a-93dc-11779419b467/195.jpg
71bf182f-98cc-494a-93dc-11779419b467/65.jpg
358fff20-07b8-4322-b268-5ab61f0beaf9/195.jpg
358fff20-07b8-4322-b268-5ab61f0beaf9/65.jpg
87a29a48-d8fb-420e-b0db-12b920d9527c/195.jpg
87a29a48-d8fb-420e-b0db-12b920d9527c/65.jpg
e121656b-3c44-4e66-bf28-3ab58d4d6230/195.jpg
e121656b-3c44-4e66-bf28-3ab58d4d6230/65.jpg
11bfa396-900c-4c58-824b-73015b28ffb4/195.jpg
11bfa396-900c-4c58-824b-73015b28ffb4/65.jpg
9e80b5ce-03d2-4b7c-9138-a02b4355dde2/195.jpg
9e80b5ce-03d2-4b7c-9138-a02b4355dde2/65.jpg
efc7f5e6-ca60-4569-90d6-76670dd2c91d/195.jpg
efc7f5e6-ca60-4569-90d6-76670dd2c91d/65.jpg
c1bf8c3c-d817-48ae-bfce-bcb79543eaa6/195.jpg
c1bf8c3c-d817-48ae-bfce-bcb79543eaa6/65.jpg
7ee39280-6401-41ab-b868-02b254b57c0f/195.jpg
7ee39280-6401-41ab-b868-02b254b57c0f/65.jpg
bf62f5a3-5d98-47c5-8d66-05f0c06e5a01/195.jpg
bf62f5a3-5d98-47c5-8d66-05f0c06e5a01/65.jpg
87e02eab-d8ee-4332-99c2-9bf8d1820856/195.jpg
87e02eab-d8ee-4332-99c2-9bf8d1820856/65.jpg
98f4c705-ff67-4697-88d2-43479f7c537b/195.jpg
98f4c705-ff67-4697-88d2-43479f7c537b/65.jpg
a9f520eb-50fd-4806-b053-2f495d833261/195.jpg
a9f520eb-50fd-4806-b053-2f495d833261/65.jpg
208ec0a3-1d4f-4fd3-9c6b-d6f03ff2d00b/195.jpg
208ec0a3-1d4f-4fd3-9c6b-d6f03ff2d00b/65.jpg
d7c43d71-5564-4e12-a3f1-f78777deab1c/195.jpg
d7c43d71-5564-4e12-a3f1-f78777deab1c/65.jpg
6320515e-b452-4007-9f43-c6c5e8512fb5/195.jpg
6320515e-b452-4007-9f43-c6c5e8512fb5/65.jpg
7d296db1-5654-4fd2-b86f-956fd900d165/195.jpg
7d296db1-5654-4fd2-b86f-956fd900d165/65.jpg
908f6d73-0954-48e5-8676-7378393d78d5/195.jpg
908f6d73-0954-48e5-8676-7378393d78d5/65.jpg
8b96d999-7d97-43b6-904d-f00996db06d8/195.jpg
8b96d999-7d97-43b6-904d-f00996db06d8/65.jpg
f4edd4e2-9d7c-48d6-8b33-6a15fb85d93f/195.jpg
f4edd4e2-9d7c-48d6-8b33-6a15fb85d93f/65.jpg
b82bddaa-6587-43a7-a204-9ba1ca3662fa/195.jpg
b82bddaa-6587-43a7-a204-9ba1ca3662fa/65.jpg
7ccae90f-9876-419b-a780-796b796b6783/195.jpg
7ccae90f-9876-419b-a780-796b796b6783/65.jpg
a985f44d-7935-4378-af49-7d7a1da329b7/195.jpg
a985f44d-7935-4378-af49-7d7a1da329b7/65.jpg
44bc33fd-67b3-4bb1-a6fe-4d4fb0aef238/195.jpg
44bc33fd-67b3-4bb1-a6fe-4d4fb0aef238/65.jpg
b5007a7d-3e85-4ed6-bcc3-67c8cd54c58c/195.jpg
b5007a7d-3e85-4ed6-bcc3-67c8cd54c58c/65.jpg
22c38b3b-858a-41f6-946a-9283c0b23ec1/195.jpg
22c38b3b-858a-41f6-946a-9283c0b23ec1/65.jpg
5633b5b3-b602-41a9-b65d-17471b45df07/195.jpg
5633b5b3-b602-41a9-b65d-17471b45df07/65.jpg
85537d1c-23ec-402d-98b3-9f682ae954e5/195.jpg
85537d1c-23ec-402d-98b3-9f682ae954e5/65.jpg
62174b90-6ea8-48f1-8317-abf8eb654cfc/195.jpg
62174b90-6ea8-48f1-8317-abf8eb654cfc/65.jpg
d50cf2af-5312-4581-b004-380dc10eb802/195.jpg
d50cf2af-5312-4581-b004-380dc10eb802/65.jpg
5cf67506-c281-4fc2-b6b2-20426142a1cd/195.jpg
5cf67506-c281-4fc2-b6b2-20426142a1cd/65.jpg
72000112-dea6-4262-ba7c-e9dbcf98f98c/195.jpg
72000112-dea6-4262-ba7c-e9dbcf98f98c/65.jpg
d6cce085-1106-4d2d-9f75-a9592cba59f9/195.jpg
d6cce085-1106-4d2d-9f75-a9592cba59f9/65.jpg
a048d035-37d0-463b-b9c7-73d73595a82e/195.jpg
a048d035-37d0-463b-b9c7-73d73595a82e/65.jpg
2dd163ac-49ae-43e8-922b-ee08c750b313/195.jpg
2dd163ac-49ae-43e8-922b-ee08c750b313/65.jpg
c5fcaefd-93a3-410f-8d34-99e77ea017ef/195.jpg
c5fcaefd-93a3-410f-8d34-99e77ea017ef/65.jpg
)
    s3 = AWS::S3.new
    bucket = s3.buckets['fairmarketfantasy-prod']
    File.open(path) do |f|
      doc = Nokogiri::XML(f)
      doc.css('asset link').each do |link|
        href = link.attributes['href'].value # "/headshot/23c9e491-bf62-48e2-abc3-057b50dc1142/195.jpg" 
        href = href.gsub("/headshot/", "")
        next if uploaded.include?(href)
        puts href
        url = "http://api.sportsdatallc.org/nfl-images-p1/headshot/#{href}?api_key=yq9uk9qu774eygre2vg2jafe"
        open(url) do |img|
          begin
            bucket.objects["headshots/#{href}"].write(img.read)
            uploaded << href
          rescue => e
            puts e.message
            retry
          end
        end
      end
    end
  end
end
