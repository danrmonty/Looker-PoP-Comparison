# Implementation details here: https://github.com/caitlinkedi/Looker-PoP-Comparison

# The SQL generates a list of integers from 0 to the number defined by the user via
# parameters for both the anchor date range breakdown and the number of time periods
# being compared.  Then it cross joins them so we have a pair for each segment in each
# comparison period that we can use to calculate the needed values for display.

view: _pop_compare {
  label: "PoP Comparison"
  derived_table: {
    datagroup_trigger: 12hour_refresh
    create_process: {
      sql_step: set date_range =  (select datediff({% parameter anchor_breakdown_type %},TO_DATE({% date_start anchor_date_range %}),TO_DATE({% date_end anchor_date_range %}))) ;;
      sql_step: CREATE TABLE ${SQL_TABLE_NAME} AS
        SELECT
          periods.period_num
          ,anchors.anchor_segment + 1 as anchor_segment
        FROM (select seq4() as period_num from table(generator(rowcount => {% parameter num_comparison_periods %}))) as periods
        CROSS JOIN (select seq4() as anchor_segment from table(generator(rowcount => $date_range))) as anchors
        ;;
      }
  }

#       FROM UNNEST(GENERATE_ARRAY(0,{% parameter num_comparison_periods %})) as period_num
#         UNNEST(GENERATE_ARRAY(0
#               ,DATETIME_DIFF(DATETIME({% date_end anchor_date_range %})
#                             ,DATETIME({% date_start anchor_date_range %})
#                             ,{% parameter anchor_breakdown_type %}))

  dimension: period_num {
    hidden: yes
    sql: ${TABLE}.period_num ;;
    type: number}
  dimension: anchor_segment {
    hidden: yes
    sql: ${TABLE}.anchor_segment ;;
    type: number}

  filter: anchor_date_range {
    type: date
    label: "1. Anchor date range"
    description: "Select the date range you want to compare. Make sure any other date filters include this period or are removed."
  }
  parameter: anchor_breakdown_type {
    type: unquoted
    label: "2. Show totals by"
    description: "Choose how you would like to break down the values in the anchor date range."
    allowed_value: {label: "Year" value: "YEAR"}
    allowed_value: {label: "Quarter" value: "QUARTER"}
    allowed_value: {label: "Month" value: "MONTH"}
    allowed_value: {label: "Week" value: "WEEK"}
    allowed_value: {label: "Day" value: "DAY"}
#     allowed_value: {label: "Hour" value: "HOUR"}
    default_value: "DAY"}
  parameter: comparison_period_type {
    type: unquoted
    label: "3. Compare to previous"
    description: "Choose the period you want to compare the anchor date range against."
    allowed_value: {label: "Year" value: "YEAR"}
    allowed_value: {label: "Quarter" value: "QUARTER"}
    allowed_value: {label: "Month" value: "MONTH"}
    allowed_value: {label: "Week" value: "WEEK"}
    allowed_value: {label: "Day" value: "DAY"}
    default_value: "MONTH"}
  parameter: num_comparison_periods {
    type: number
    label: "4. Number of past periods"
    description: "Choose how many past periods you want to compare the anchor range against."
    default_value: "1"}

  # Create some helpful values related to the anchor breakdown type (abt)
  # and comparison period type (cpt) fields for later use (see below)
  dimension: abt_format {
    type: string
    hidden: yes
    sql:
      {% if anchor_date_range._is_filtered %}
        {% if anchor_breakdown_type._parameter_value == 'YEAR' %} 'YEAR' --YYYY, e.g. 2019
        {% elsif anchor_breakdown_type._parameter_value == 'MONTH'
          OR anchor_breakdown_type._parameter_value == 'QUARTER' %} 'MONTH' --MON YYYY, e.g. JUN 2019
        {% else %} 'DAY' --MM/DD/YY, e.g. 06/12/19
        {% endif %}
      {% else %} NULL
      {% endif %}
      ;;}
#         -- {% elsif anchor_breakdown_type._parameter_value == 'HOUR' %} 'MM/DD %r' --MM/DD 12hrAM/PM, e.g. 06/12 1:00 PM
  dimension: cpt_name {
    type: string
    hidden: yes
    sql:
      {% if anchor_date_range._is_filtered %}
        {% if comparison_period_type._parameter_value == 'YEAR' %} 'Year'
        {% elsif comparison_period_type._parameter_value == 'QUARTER' %} 'Quarter'
        {% elsif comparison_period_type._parameter_value == 'MONTH' %} 'Month'
        {% elsif comparison_period_type._parameter_value == 'WEEK' %} 'Week'
        {% else %} 'Day'
        {% endif %}
      {% else %} NULL
      {% endif %}
      ;;}

  # Define and then nicely format values included in the anchor range breakdown segments
  # for use on a chart axis. Starting with the filter end date, this produces all the date
  # segments needed in the anchor range, then truncates them off to the desired granularity,
  # then formats them based on the definitions in the abt_format dimension above.
      dimension: anchor_dates_unformatted {
        hidden: yes
        type: date_raw
        sql:
              {% if anchor_date_range._is_filtered %}
              TRUNC(
                DATEADD({% parameter anchor_breakdown_type %}, -1*${anchor_segment},
                  TO_DATE({% date_end anchor_date_range %})
                )
              ,'{% parameter anchor_breakdown_type %}')
              {% else %} NULL
              {% endif %}
              ;;}
      dimension: anchor_dates {
        type: string
        order_by_field: anchor_dates_unformatted
        sql:
              {% if anchor_date_range._is_filtered %}
              DATE_TRUNC(${abt_format},${anchor_dates_unformatted})
              {% else %} NULL
              {% endif %}
              ;;}

          # Give nice names to the comparison periods so they can be shown cleanly on charts.
          dimension: comparison_period_pivot  {
            type: string
            description: "Pivot me! These are the periods being compared."
            order_by_field: period_num
            sql:
                  {% if anchor_date_range._is_filtered %}
                  CASE ${period_num}
                    WHEN 0 THEN CONCAT('Anchor ', ${cpt_name})
                    WHEN 1 THEN CONCAT('1 ',${cpt_name}, ' prior')
                    ELSE CONCAT(CAST(${period_num} as STRING),' ',${cpt_name}, 's prior')
                  END
                  {% else %} NULL
                  {% endif %}
                  ;;}

            }#End View
