module NestedAncestryCommon
  extend ActiveSupport::Concern

  included do
    audited :except => [:title], :allow_mass_assignment => true
    has_associated_audits
    has_ancestry :orphan_strategy => :restrict

    before_validation :set_title
    after_save :set_other_titles, :on => [:update, :destroy]
    after_save :update_matchers, :on => :update, :if => Proc.new { |obj| obj.title_changed? }

    validates :name, :presence => true, :uniqueness => {:scope => :ancestry, :case_sensitive => false}
    validates :title, :presence => true, :uniqueness => true
    validate :title_and_lookup_key_length

    scoped_search :on => :title, :complete_value => true, :default_order => true
    scoped_search :on => :name, :complete_value => :true

    # attribute used by *_names and *_name methods.  default is :name
    attr_name :title
  end

  # override title getter
  def title
    read_attribute(:title) || get_title
  end

  alias_method :to_label, :title

  def get_title
    return name if ancestry.empty?
    ancestors.map { |a| a.name + '/' }.join + name
  end

  alias_method :get_label, :get_title

  def to_param
    Parameterizable.parameterize("#{id}-#{get_title}")
  end

  module ClassMethods
    def nested_attribute_for(*opts)

      opts.each do |field|

        # Example method
        # def inherited_compute_profile_id
        #   read_attribute(:compute_profile_id) || nested_compute_profile_id
        # end
        define_method "inherited_#{field}" do
          read_attribute(field) || nested(field)
        end

        # Example method - only override method generated by assocation if there is ancestry.
        # if ancestry.present?
        #   def compute_profile
        #    ComputeProfile.find_by_id(inherited_compute_profile_id)
        #  end
        # end
        if md = field.to_s.match(/(\w+)_id$/)
          define_method md[1] do
            if ancestry.present?
              klass = md[1]
              klass = "smart_proxy" if ["puppet_proxy", "puppet_ca_proxy"].include?(md[1])
              klass.classify.constantize.find_by_id(send("inherited_#{field}"))
            else
              # () is required. Otherwise, get RuntimeError: implicit argument passing of super from method defined by define_method() is not supported. Specify all arguments explicitly.
              super()
            end
          end
        end

      end
    end
  end

  def nested(attr)
    self.class.sort_by_ancestry(ancestors.where("#{attr} is not NULL")).last.try(attr) if ancestry.present?
  end

  private

  def set_title
    self.title = get_title if (name_changed? || ancestry_changed? || title.blank?)
  end

  def set_other_titles
    if name_changed? || ancestry_changed?
      self.class.where('ancestry IS NOT NULL').each do |obj|
        if obj.path_ids.include?(self.id)
          obj.update_attributes(:title => obj.get_title)
        end
      end
    end
  end

  def obj_type
    self.class.to_s.downcase
  end

  def update_matchers
    lookup_values = LookupValue.where(:match => "#{obj_type}=#{title_was}")
    lookup_values.update_all(:match => "#{obj_type}=#{title}")
  end

  # This validation is because lookup_value has an attribute `match` that cannot be turned to a test field do to
  # an index set on it and problems with mysql indexes on test fields.
  # If the index can be fixed, `match` should be turned into text and then this validation should be removed
  def title_and_lookup_key_length
    if name.present?

      # The match is defined (example for hostgroup) "hostgroup=" + hostgroup.title so the length of "hostgroup=" needs to be added to the
      # total length of the matcher that will be created
      # obj_type will be "hostgroup" and another character is added for the "=" sign
      length_of_matcher = obj_type.length + 1

      # the parent title + "/" is added to the name to create the title
      length_of_matcher += parent.title.length + 1 if parent.present?


      max_length_for_name = 255 - length_of_matcher
      current_title_length = max_length_for_name - name.length

      errors.add(:name, n_("is too long (maximum is 1 character)", "is too long (maximum is %s characters)", max_length_for_name) % max_length_for_name) if current_title_length < 0
    end
  end

end
