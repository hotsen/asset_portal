require 'open-uri'

task wipe_neo4j_database: :environment do
  puts 'Are you SURE you want to wipe your Neo4j database?'
  print "#{Rails.env} environment (y/n)? > "
  exit! unless %w(y yes).include?(STDIN.gets.chomp.downcase)

  Neo4j::Session.current.query('MATCH n OPTIONAL MATCH n-[r]-() DELETE n, r')

  puts 'Done!'
end

def random_created_and_updated_ats_hash
  updated_at = Time.now - rand(6.months)

  created_at = if rand < 0.8
                 updated_at
               else
                 updated_at - rand(3.months)
               end

  {created_at: created_at.to_i, updated_at: updated_at.to_i}
end

def load_from_json(model_class)
  filename = model_class.to_s.tableize + '.json'

  JSON.parse(Rails.root.join('db').join(filename).read).each do |object_data|
    object_data.merge!(random_created_and_updated_ats_hash)
    object = model_class.create(object_data)

    yield object if block_given?

    print '.'
  end
end

def random_nodes(model_class, max)
  model_class.limit(rand(max) + 1).order('rand()').to_a
end

def cover_url(cover_i, size)
  "https://covers.openlibrary.org/w/id/#{cover_i}-#{size}.jpg"
end

CACHE = ActiveSupport::Cache::FileStore.new(Rails.root.join('cache'))

def uncached_cover_data(cover_i)
  data = nil
  %w(L M S).detect do |size|
    begin
      data = open(cover_url(cover_i, size))
    rescue Errno::ECONNRESET
      nil
    end
  end
  data.read if data
end

def cover_data(cover_i)
  return nil if cover_i.blank?

  CACHE.fetch(cover_i, expires_in: 1.month) do
    uncached_cover_data(cover_i)
  end || uncached_cover_data(cover_i)
end

CATEGORY_ICON_CLASSES = {'Graph theory' => 'share alternate',
                         'Accessible book' => 'child',
                         'Protected DAISY' => 'child',
                         'Data processing' => 'database',
                         'Mathematics' => 'calculator',
                         'Science/Mathematics' => 'doctor',
                         'Chemistry' => 'fire',
                         'Graph theory -- Data processing' => 'database',
                         'Topological graph theory' => 'share alternate',
                         'Discrete Mathematics' => 'signal',
                         'Topology' => 'share alternate'
}

task load_sample_data: :environment do
  puts 'Creating sample data.'
  puts 'To wipe your database first use the `wipe_neo4j_database` rake task.'
  puts

  puts 'Creating groups'
  user_group = Group.create(name: 'User group')
  power_user_group = Group.create(name: 'Power user group')
  admin_group = Group.create(name: 'Admin')

  admin_group.sub_groups = [user_group, power_user_group]

  # Data from https://openlibrary.org/search.json?title=graphs+theory
  book_search_data = JSON.parse(Rails.root.join('db', 'book_search.json').read)

  Book.delete_all

  puts
  puts 'Creating assets'
  book_search_data['docs'].each do |book_data|
    cover_data_string = cover_data(book_data['cover_i'])
    isbn13 = Array(book_data['isbn']).detect { |isbn| isbn.size == 13 }

    authors = Array(book_data['author_name']).map do |author_name|
      Person.merge(name: author_name, private: false)
    end.uniq
    contributors = Array(book_data['contributor']).map do |contributor_name|
      Person.merge(name: contributor_name, private: false)
    end.uniq

    asset = Book.create(
      title: book_data['title'],
      private: (rand < 0.2),
      image: cover_data_string && StringIO.new(cover_data_string),
      isbn13: isbn13,
      authors: authors,
      contributors: contributors,
      publish_date: book_data['publish_date'] && book_data['publish_date'][0]
    )

    (book_data['subject'] || []).each do |subject_name|
      category = Category.find_or_create({standardized_name: subject_name.downcase}, name: subject_name, icon_class: CATEGORY_ICON_CLASSES[subject_name])
      asset.categories << category
    end
    putc '.'
  end

  # puts
  # puts 'Creating assets'
  # load_from_json(Asset) do |asset|
  #   asset.allowed_groups << user_group if rand < 0.5
  #   asset.allowed_groups << power_user_group if rand < 0.2
  # end

  # puts
  # puts 'Creating categories'
  # load_from_json(Category) do |category|
  #   category.assets = random_nodes(Asset, 50)
  # end

  puts
  puts 'Creating users'
  asset_count = Asset.count
  load_from_json(User) do |user|
    user.created_assets = random_nodes(Asset, 5) if rand < 0.15
    # user.allowed_assets = random_nodes(Asset, 10) if rand < 0.15
    user.viewed_assets  = random_nodes(Asset, asset_count / 3) if rand < 0.7
    # user.groups << [user_group, power_user_group].sample if rand < 0.2
    # user.groups << [admin_group] if rand < 0.05
  end
end
