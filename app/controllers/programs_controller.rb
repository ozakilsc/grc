# Author:: Miron Cuperman (mailto:miron+cms@google.com)
# Copyright:: Google Inc. 2012
# License:: Apache 2.0

require 'csv'

# Browse programs
class ProgramsController < ApplicationController
  include ApplicationHelper
  include ProgramsHelper
  include ImportHelper

  PROGRAM_MAP = Hash[*%w(Type type Code slug Title title Description description Company company Version version Start start_date Stop stop_date Kind kind Audit-Start audit_start_date Audit-Frequency audit_frequency Audit-Duration audit_duration Created created_at Updated updated_at)]

  SECTION_MAP = Hash[*%w(Code slug Title title Description description Notes notes Created created_at Updated updated_at)]

  # FIXME: Decide if the :section, controls, etc.
  # methods should be moved, and what access controls they
  # need.
  before_filter :load_program, :only => [:show,
                                         :export,
                                         :tooltip,
                                         :edit,
                                         :update,
                                         :delete,
                                         :destroy,
                                         :sections,
                                         :controls,
                                         :section_controls,
                                         :control_sections,
                                         :category_controls]

  access_control :acl do
    allow :superuser

    allow :create, :create_program, :to => [:create,
                                   :new]
    allow :read, :read_program, :of => :program, :to => [:show,
                                                  :tooltip,
                                                  :sections,
                                                  :controls,
                                                  :section_controls,
                                                  :control_sections,
                                                  :category_controls]

    allow :update, :update_program, :of => :program, :to => [:edit,
                                                    :update,
                                                    :import,
                                                    :export]
  end

  layout 'dashboard'

  def index
    @programs = Program
    if params[:relevant_to]
      @programs = @programs.relevant_to(Product.find(params[:relevant_to]))
    end
    if params[:s]
      @programs = @programs.db_search(params[:s])
    end
    @programs = allowed_objs(@programs.all, :read)
  end

  def show
    @stats = program_stats(@program)
  end

  def new
    @program = Program.new(program_params)

    render :layout => nil
  end

  def edit
    render :layout => nil
  end

  def create
    @program = Program.new(program_params)

    respond_to do |format|
      if @program.save
        flash[:notice] = "Program was created successfully."
        format.json { render :json => @program.as_json(:root => false), :location => flow_program_path(@program) }
        format.html do
          redirect_to flow_program_path(@program)
        end
      else
        flash[:error] = "There was an error creating the program"
        format.html do
          if request.xhr?
            render :layout => nil, :status => 400
          end
        end
      end
    end
  end

  def update
    if !params[:program]
      return 400
    end

    respond_to do |format|
      if @program.authored_update(current_user, program_params)
        flash[:notice] = 'Program was successfully updated.'
        format.json { render :json => @program.as_json(:root => nil) }
        format.html { ajax_refresh }
      else
        flash[:error] = "There was an error updating the program"
        format.html { render :layout => nil, :status => 400 }
      end
    end
  end

  def export
    respond_to do |format|
      format.csv do
        self.response.headers['Content-Type'] = 'text/csv'
        headers['Content-Disposition'] = "attachment; filename=\"#{@program.slug}.csv\""
        self.response_body = Enumerator.new do |out|
          out << CSV.generate_line(PROGRAM_MAP.keys)
          keys = PROGRAM_MAP.keys
          keys.shift
          values = keys.map { |key| @program.send(PROGRAM_MAP[key]) }
          values.unshift("Program")
          out << CSV.generate_line(values)
          out << CSV.generate_line([])
          out << CSV.generate_line(SECTION_MAP.keys)
          @program.sections.each do |s|
            values = SECTION_MAP.keys.map { |key| s.send(SECTION_MAP[key]) }
            out << CSV.generate_line(values)
          end
        end
      end
    end
  end

  def delete
    @model_stats = []
    @relationship_stats = []
    @model_stats << [ 'Section', @program.sections.count ]
    @model_stats << [ 'Control', @program.controls.count ]
    @model_stats << [ 'Cycle', @program.cycles.count ]
    @relationship_stats << [ 'Document', @program.documents.count ]
    @relationship_stats << [ 'Category', @program.categories.count ]
    @relationship_stats << [ 'Person', @program.people.count ]
    respond_to do |format|
      format.json { render :json => @program.as_json(:root => nil) }
      format.html do
        render :layout => nil, :template => 'shared/delete_confirm',
          :locals => { :model => @program, :url => flow_program_path(@program), :models => @model_stats, :relationships => @relationship_stats }
      end
    end
  end

  def destroy
    @program.destroy
    flash[:notice] = "Program deleted"
    respond_to do |format|
      format.html { redirect_to programs_dash_path }
      format.json { render :json => @program.as_json(:root => nil) }
    end
  end

  def import
    upload = params["upload"]
    if upload
      file = upload.read
      import = read_import(CSV.parse(file))
      @messages = import[:messages]
      do_import(import, params[:confirm].blank?)
      @errors = import[:errors]
      @creates = import[:creates]
      @updates = import[:updates]
      render 'import_result', :layout => false
    end
  end

  def handle_option(attrs, name, messages)
    name_s = name.to_s
    if attrs[name_s]
      value = Option.where(:role => name, :title => attrs[name_s]).first
      if value.nil?
        messages << "Unknown #{name_s} option '#{attrs[name_s]}'"
      end
      attrs[name_s] = value
    end
  end

  def do_import(import, check_only)
    import[:errors] = {}
    import[:updates] = []
    import[:creates] = []
    attrs = import[:program]
    attrs.delete(nil)
    attrs.delete("created_at")
    attrs.delete("updated_at")
    handle_option(attrs, :audit_duration, import[:messages])
    handle_option(attrs, :audit_frequency, import[:messages])
    slug = attrs["slug"]
    if slug.blank?
      import[:messages] << "missing program slug" unless key
    else
      @program = Program.find_by_slug(slug)
      if @program
        @program.assign_attributes(attrs, :without_protection => true)
        import[:updates] << slug
      else
        @program = Program.new
        @program.assign_attributes(attrs, :without_protection => true)
        import[:creates] << slug
      end
      import[:errors][slug] = @program.errors.full_messages unless @program.valid?
      @program.save unless check_only
    end

    @sections = []
    import[:sections].each do |attrs|
      attrs.delete(nil)
      slug = attrs["slug"]
      if slug.blank?
        import[:messages] << "missing program slug" unless key
      else
        section = Section.find_by_slug(slug)
        if section
          section.assign_attributes(attrs, :without_protection => true)
          import[:updates] << slug
        else
          section = Section.new
          section.assign_attributes(attrs, :without_protection => true)
          section.program = @program
          import[:creates] << slug
        end
        @sections << section
        import[:errors][slug] = section.errors.full_messages unless section.valid?
        section.save unless check_only
      end
    end
  end

  def read_import(rows)
    import = { :messages => [] }

    raise "There must be at least 3 input lines" unless rows.size >= 4

    program_headers = trim_array(rows.shift).map do |heading|
      if heading == "Type"
        key = 'type'
      else
        key = PROGRAM_MAP[heading]
        import[:messages] << "invalid program heading #{heading}" unless key
      end
      key
    end

    program_values = rows.shift

    raise "First column must be Type" unless program_headers.shift == "type"
    raise "Type must be Program" unless program_values.shift == "Program"

    import[:program] = Hash[*program_headers.zip(program_values).flatten]

    raise "There must be an empty separator row" unless trim_array(rows.shift) == []

    section_headers = trim_array(rows.shift).map do |heading|
      key = SECTION_MAP[heading]
      import[:messages] << "invalid section heading #{heading}" unless key
      key
    end

    import[:sections] = rows.map do |section_values|
      Hash[*section_headers.zip(section_values).flatten]
    end

    import
  end

  def perform_import(rows, actual)
    puts rows.size
  end

  def tooltip
    render :layout => '_tooltip', :locals => { :program => @program }
  end

  def sections
    @sections = @program.sections.includes(:controls => :implementing_controls)
    if params[:s]
      @sections = @sections.fulltext_search(params[:s])
    end
    @sections = allowed_objs(@sections.all.sort_by(&:slug_split_for_sort), :read)
    render :layout => nil, :locals => { :sections => @sections }
  end

  def controls
    @controls = @program.controls.includes(:implementing_controls)
    if params[:s]
      @controls = @controls.fulltext_search(params[:s])
    end
    @controls = allowed_objs(@controls.all.sort_by(&:slug_split_for_sort), :read)
    render :layout => nil, :locals => { :controls => @controls }
  end

  def section_controls
    if @program.company?
      @sections = @program.controls.includes(:implemented_controls => { :control_sections => :section }).map { |cc| cc.implemented_controls.map { |ic| ic.control_sections.map { |cs| cs.section } }.flatten }.flatten.uniq
    else
      @sections = @program.sections.includes(:controls => :implementing_controls).all
    end
    @sections.sort_by(&:slug_split_for_sort)
    @sections = allowed_objs(@sections, :read)
    render :layout => nil, :locals => { :sections => @sections }
  end

  def control_sections
    @controls = @program.controls.includes(:sections)
    if params[:s]
      @controls = @controls.fulltext_search(params[:s])
    end
    @controls = allowed_objs(@controls.all.sort_by(&:slug_split_for_sort), :read)
    render :layout => nil, :locals => { :controls => @controls }
  end

  def category_controls
    @category_tree = Category.roots.all.map do |category|
      branches = category.children.all.map do |subcategory|
        controls = subcategory.controls.where(:program_id => @program.id).all
        if !controls.empty?
          [subcategory, controls]
        end
      end.compact
      if !branches.empty?
        [category, branches]
      end
    end.compact

    uncategorized_controls = Control.
      includes(:categorizations).
      where(
        :program_id => @program.id,
        :categorizations => { :categorizable_id => nil }).
      all

    if !uncategorized_controls.empty?
      @category_tree.push([nil, uncategorized_controls])
    end

    render :layout => nil, :locals => { }
  end

  private

    def load_program
      @program = Program.find(params[:id])
    end

    def program_params
      program_params = params[:program] || {}
      if program_params[:type]
        program_params[:company] = (program_params.delete(:type) == 'company')
      end
      %w(start_date stop_date audit_start_date).each do |field|
        parse_date_param(program_params, field)
      end
      %w(kind audit_frequency audit_duration).each do |field|
        parse_option_param(program_params, field)
      end
      program_params
    end

end
