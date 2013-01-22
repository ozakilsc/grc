module ImportHelper
  def trim_array(a)
    while !a.empty? && a.last.blank?
      a.pop
    end
    a
  end

  def validate_import_slug(object, object_name, expected_slug)
    raise ImportException.new("#{object_name} Code column does not exist") unless object["slug"]
    raise ImportException.new("#{object_name} Code does not match current program") unless object["slug"] == expected_slug
  end

  def validate_import_type(object, expected_type)
    type = object.delete("type")
    raise ImportException.new("First column must be Type") unless type
    raise ImportException.new("Type must be #{expected_type}") unless type == expected_type
  end

  def read_import_headers(import, import_map, object_name, rows)
    trim_array(rows.shift).map do |heading|
      heading = (heading || "").strip
      key = import_map[heading]
      if !key
        found = false
        prefix = "Invalid #{object_name} headings: "
        import[:messages].each_with_index do |message, i|
          if message.starts_with?(prefix)
            import[:messages][i] = message + ", \"#{heading}\""
            found = true
          end
        end
        if !found
          import[:messages] << prefix + "\"#{heading}\""
        end
      end
      key
    end
  end

  def read_import(import, import_map, object_name, rows)
    headers = read_import_headers(import, import_map, object_name, rows)

    non_empty_rows = rows.find_all { |r| (r.reject &:blank?).any? }
    import[object_name.pluralize.to_sym] = non_empty_rows.map do |values|
      row = {}
      headers.zip(values).each do |k, v|
        if row.has_key?(k)
          row[k] = "#{row[k]},#{v}"
        else
          row[k] = v
        end
      end
      row['slug'] = row['slug'].upcase if row.has_key?('slug') && !row['slug'].nil?
      row
    end
  end

  def render_import_error(message=nil)
    render '/error/import_error', :layout => false, :locals => { :message => message }
  end

  # if warning_key is set warnings will be assigned to this key instead of actual key
  def handle_import_person(attrs, key, warnings, warning_key = nil)
    email = (attrs[key]||"").strip
    warning_key ||= key

    unless email.nil?
      if email.include?('@')
        attrs[key] = Person.find_or_create_by_email!({:email => email})
      elsif email == ""
        attrs[key] = nil
      elsif email !~ / /
        email = "#{email}@#{ENV['DEFAULT_DOMAIN']}"
        attrs[key] = Person.find_or_create_by_email!({:email => email})
      else
        attrs[key] = nil
        warnings[warning_key.to_sym] ||= []
        warnings[warning_key.to_sym] << "invalid email"
      end
    end
  end

  # NOTE: This depends on person having been looked up and the person object put in attrs[key]
  def handle_import_object_person(object, attrs, key, role)
    person = attrs.delete(key)
    existing = object.object_people.detect {|x| x.role == role}

    if existing
      if existing.person != person
        existing.destroy
      else
        # Already there
        return
      end
    end

    if person
      object.object_people.new({:role => role, :person => person}, :without_protection => true)
    end
  end

  def strip_split(str)
      str.split(',').map {|x| x.strip}.reject {|x| x.blank?}
  end

  def handle_import_category(object, attrs, key, category_scope_id)
    category_string = attrs.delete(key)

    if category_string.present?
      names = strip_split(category_string)
      categories = names.map {|category| Category.find_or_create_by_name_and_scope_id({:name => category, :scope_id => category_scope_id})}
      object.categories = (object.categories + categories).uniq
    end
  end

  def handle_import_systems(object, attrs, key)
    systems_string = attrs.delete(key)

    unless systems_string.nil?
      slugs = strip_split(systems_string)
      slugs = slugs.map {|x| x.upcase}
      systems = slugs.map do |slug|
        system = System.find_or_create_by_slug({:slug => slug, :title => slug, :infrastructure => false})
        system
      end
      object.systems = systems.uniq
    end
  end

  def handle_boolean(attrs, key)
    if attrs.has_key?(key)
      attrs[key] = (attrs[key] == 'yes' || attrs[key] == '1' || attrs[key] == 'true')
    end
  end

  def handle_import_sub_systems(object, attrs, key)
    systems_string = attrs.delete(key)

    unless systems_string.nil?
      slugs = strip_split(systems_string)
      slugs = slugs.map {|x| x.upcase}
      systems = slugs.map do |slug|
        system = System.find_or_create_by_slug({:slug => slug, :title => slug, :infrastructure => false})
        system
      end
      object.sub_systems = systems.uniq
    end
  end

  def handle_import_relationships(object, related_string, related_class, relationship_type)
    return unless object.id
    if related_string.present?
      slugs = strip_split(related_string)
      slugs = slugs.map {|x| x.upcase}
      relateds = slugs.each do |slug|
        related = related_class.find_or_create_by_slug({:slug => slug, :title => slug})
        attrs = {:source_id => object.id, :source_type => object.class.name, :destination_id => related.id, :destination_type => related_class.name, :relationship_type_id => relationship_type}
        unless Relationship.exists?(attrs)
          Relationship.create!(attrs)
        end
      end
    end
  end

  def handle_import_documents(object, attrs, key)
    documents_string = attrs.delete(key)

    if documents_string.present?
      documents = parse_document_reference(documents_string).map do |attrs|
        doc = Document.find_or_create_by_link(attrs)
        doc
      end
      object.documents = documents
    end
  end

  def parse_document_reference(ref_string)
    ref_string.split("\n").map do |ref|
      ref =~ /(.*)\[(\S+)(:?.*)\](.*)/
      link = $2.nil? ? '' : $2
      if link.start_with?('//')
        link = "file:" + link
      end
      { :description => ($1.nil? ? '' : $1) + ($4.nil? ? '' : $4),
        :link => link, :title => $3.present? ? $3.strip : link }
    end.reject {|x| x[:link].blank?}
  end

  def handle_import_document_reference(object, attrs, key, warnings)
    ref_string = attrs.delete(key)
    if ref_string.present?
      documents = parse_document_reference(ref_string).map do |ref|
        begin
          Document.find_or_create_by_link!(ref)
        rescue
          warnings[key.to_sym] ||= []
          warnings[key.to_sym] << "invalid reference URL"
          nil
        end
      end.compact
      object.documents = documents
    end
  end

  def handle_option(attrs, name, warnings, role = nil)
    role ||= name.to_sym
    if attrs[name]
      value = Option.where(:role => role, :title => attrs[name]).first
      if value.nil?
        warnings[name.to_sym] ||= []
        warnings[name.to_sym] << "Unknown #{role} option '#{attrs[name]}'"
      end
      attrs[name] = value
    end
  end

  # makes sure that date attribute is parsable by Rails
  def handle_date(attrs, key, warnings)
    if attrs.has_key?(key) && attrs[key].present?
      begin
        Date.parse(attrs[key])
      rescue => e
        warnings[key.to_sym] ||= []
        warnings[key.to_sym] << "#{e}, use YYYY-MM-DD format"
      end
    end
  end
end
