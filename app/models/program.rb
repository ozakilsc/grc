# A Program which links Directives
#
# The top of the Program -> Directive -> Control hierarchy
class Program < ActiveRecord::Base
  include CommonModel
  include SluggedModel
  include SearchableModel
  include AuthorizedModel
  include RelatedModel
  include SanitizableAttributes

  KINDS = [
    "Directive",
    "Company Controls",
  ]

  attr_accessible :title, :slug, :description, :start_date, :stop_date, :url, :kind

  has_many :program_directives, :dependent => :destroy
  has_many :directives, :through => :program_directives

  is_versioned_ext

  sanitize_attributes :description

  validates :title,
    :presence => { :message => "needs a value" }

  def display_name
    slug
  end

  def company_controls?
    kind == "Company Controls"
  end

  def self.all_company_control_programs_first
    programs = self.all
    programs =
      programs.select { |p| p.company_controls? } +
      programs.reject { |p| p.company_controls? }
  end

  def impact_scope_for_directives
    near_model = Directive
    near_ids = directive_ids

    data = near_model.valid_relationships.inject({}) do |memo, vr|
      memo[vr[:related_model]] ||= {}
      memo[vr[:related_model]][vr[:relationship_type]] ||= []

      objects = memo[vr[:related_model]][vr[:relationship_type]]

      far_model = vr[:related_model]

      if vr[:related_model_endpoint] == :destination
        Relationship.where(:source_type => near_model, :source_id => near_ids, :destination_type => far_model).all.each do |rel|
          objects.push(rel.destination)
        end
      elsif vr[:related_model_endpoint] == :source
        Relationship.where(:destination_type => near_model, :destination_id => near_ids, :source_type => far_model).all.each do |rel|
          objects.push(rel.source)
        end
      end

      memo
    end

    # De-duplicate objects in each relationship type's list
    data.each do |model, rels|
      rels.each do |rel_type_id, rel_objects|
        rels[rel_type_id] = rel_objects.uniq
      end
    end

    data
  end
end
