*&---------------------------------------------------------------------*
*& Report  ZBC_DOMAIN_CLASS_GENERATOR
*& GIT:            https://github.com/devbreath/DCG/blob/main/dcg.abap
*& Description:
*& Generate class with constants for domain/data element. It can used own
*& code and search dependecies of domain values via where used list
*& Writen many years ago, just cleaned and prettyficated for github now.
*&---------------------------------------------------------------------*
*& ConVista Russia
*& Gluschenko Vitaliy
*&---------------------------------------------------------------------*
REPORT zbc_domain_class_generator.

TYPE-POOLS abap.

* Simple Logger class, which support list output
CLASS lcl_list_log DEFINITION INHERITING FROM zicm_cl_application_log.
  TYPE-POOLS icon.
  PUBLIC SECTION.
    CLASS-METHODS set_log_level IMPORTING iv_level TYPE sy-msgty.
    CLASS-METHODS add_message_text IMPORTING iv_msgty TYPE sy-msgty DEFAULT 'I'
                                             iv_text  TYPE char256.
  PRIVATE SECTION.
    CLASS-DATA mv_log_level TYPE sy-msgty VALUE 'I'.
ENDCLASS.

CLASS lcl_list_log IMPLEMENTATION.

  METHOD set_log_level.
    mv_log_level = iv_level.
  ENDMETHOD.

  METHOD add_message_text.
    DATA lv_icon TYPE char10.
    DATA lv_msgty TYPE sy-msgty.

    " priorities for logging:
    " level | logging messages
    "   I   |   E W I
    "   W   |   E W
    "   E   |   E
    lv_msgty = iv_msgty.
    TRANSLATE mv_log_level USING 'I3W2E1'.
    TRANSLATE lv_msgty USING 'I3W2E1'.
    IF mv_log_level < lv_msgty.
      RETURN.
    ENDIF.
    CASE iv_msgty.
      WHEN 'E'.
        lv_icon = icon_message_error.
      WHEN 'W'.
        lv_icon = icon_message_warning.
      WHEN 'I'.
        lv_icon = icon_message_information.
      WHEN OTHERS.
        lv_icon = icon_message_question.
    ENDCASE.

    WRITE: / lv_icon AS ICON, iv_text.

  ENDMETHOD.

ENDCLASS.

*class lcl_domainclass_generator definition deferred.
*class lcx_domainclass_generator definition inheriting from cx_static_check create private friends lcl_domainclass_generator.
*  public section.
*
*    interfaces if_t100_message .
*
*    data:
*      begin of empty_constants,
*        msgid type symsgid value 'SY',
*        msgno type symsgno value '499',
*        attr1 type scx_attrname value '',
*        attr2 type scx_attrname value '',
*        attr3 type scx_attrname value '',
*        attr4 type scx_attrname value '',
*      end of empty_constants.
*
*    methods constructor
*      importing
*        !textid   like if_t100_message=>t100key optional
*        !previous like previous optional
*        !attr1    type scx_attrname optional
*        !attr2    type scx_attrname optional.
*  protected section.
*  private section.
*
*endclass.
*
*class lcx_domainclass_generator implementation.
*
*  method constructor.
*    call method super->constructor
*      exporting
*        previous = previous.
*    clear me->textid.
*    if textid is initial.
*      if_t100_message~t100key = if_t100_message=>default_textid.
*    else.
*      if_t100_message~t100key = textid.
*    endif.
*  endmethod.
*
*endclass.

***********************************************************************
*       CLASS lcl_domainclass_generator DEFINITION
***********************************************************************
CLASS lcl_domainclass_generator DEFINITION.
  TYPE-POOLS seoo.
  PUBLIC SECTION.
    "--------------------------------------
    " TYPES
    "--------------------------------------
    " Type of name for constant attribute in the class
    TYPES ty_const_name TYPE seocpdname.
    TYPES: BEGIN OF ty_const_translation,
             lang TYPE spras,
             desc TYPE seodescr,
           END OF ty_const_translation.
    TYPES: tt_translation TYPE SORTED TABLE OF ty_const_translation WITH UNIQUE KEY lang.

    " Type of structure, which is describe a constant attribute
    TYPES: BEGIN OF ty_const,
             name  TYPE ty_const_name,
             desc  TYPE seodescr,
             type  TYPE rs38l_typ,
             value TYPE seovalue,
             trans TYPE tt_translation,
           END OF ty_const.

    CONSTANTS mc_as4local_active TYPE as4local VALUE 'A'.

    "--------------------------------------
    " Methods
    "--------------------------------------
    "! Create a new instance of object via factory method
    CLASS-METHODS get_instance RETURNING VALUE(eo_instance) TYPE REF TO lcl_domainclass_generator.
    "! Set name of data element for which will be generated an abap class
    METHODS set_de_name IMPORTING iv_name TYPE rollname.
    "! Get name generated class
    METHODS get_class_name RETURNING VALUE(ev_name) TYPE seoclsname.
    "! Generate class using data element as definition
    METHODS gen_class.

    "! Not obligated method: Set name preffix for class, which will be generated by the data element
    METHODS set_class_preffix IMPORTING VALUE(iv_value) TYPE string.
    "! Not obligated method: Set package for generated class
    METHODS set_class_package IMPORTING VALUE(iv_package) TYPE devclass.

    "! Not obligated method: Set transport for generated class
    METHODS set_class_transport IMPORTING VALUE(iv_request) TYPE trkorr.

  PRIVATE SECTION.
    "--------------------------------------
    " Types
    "--------------------------------------
    TYPES: BEGIN OF ty_reference,
             name    TYPE eu_lname,
             include TYPE programm,
           END OF ty_reference.
    TYPES tt_reference TYPE STANDARD TABLE OF ty_reference." with non-unique key name.
    TYPES tt_strings TYPE STANDARD TABLE OF char256.
    TYPES ty_error TYPE i.                          " type for errors which may generated
    "--------------------------------------
    " Constants
    "--------------------------------------
    CONSTANTS mc_class_descrip TYPE string VALUE 'Generated class for domain %domain%'. " description, which will be wrote to generated class
    CONSTANTS mc_const_preffix TYPE string VALUE 'MC_'.             " prefix for generated constant name
    CONSTANTS mc_def_lang TYPE lang VALUE 'E'.                      " default language for generated class
    CONSTANTS mc_otype_domattr TYPE char2 VALUE 'DA'.               " Data element value cross reference

    CONSTANTS mc_tag_modif TYPE string VALUE '#MODIF#'.            " tag in description of class,
    "which is restrict of regeneration
    "--------------------------------------
    " Setupable constants (it is variables, which will set only on time)
    "--------------------------------------
    DATA mv_class_preffix TYPE string VALUE 'ZDDIC_CL_'.  " prefix for generated class name
    DATA mv_package TYPE devclass VALUE 'ZZTMP_VG'. "'$TMP'.
    DATA mv_corrnr TYPE trkorr  VALUE 'DI1K901121'.   " Request number for class

    "--------------------------------------
    " Error types
    "--------------------------------------
    CONSTANTS:
      mc_error_ok      TYPE ty_error VALUE 0,   " No error, everything is ok
      mc_error_unknown TYPE ty_error VALUE 1.   " Not classified error

    "--------------------------------------
    " Data elements
    "--------------------------------------
    DATA mv_delem TYPE rollname.                                  " Name of data element for which class will be generated
    DATA mv_domain TYPE domname.
    DATA mv_clsname TYPE seoclsname.
    DATA mt_const TYPE SORTED TABLE OF ty_const WITH NON-UNIQUE KEY name.

    DATA mt_reference TYPE tt_reference.
    DATA mv_loaded_class TYPE ty_const_name.

    "! Set name of generated class
    METHODS set_class_name IMPORTING VALUE(iv_name) TYPE seoclsname.

    "! Add new constant with value and description to the list
    METHODS add_const IMPORTING iv_name  TYPE ty_const_name
                                iv_desc  TYPE seodescr
                                iv_type  TYPE rs38l_typ
                                iv_value TYPE seovalue.
    "! Method convert values, that can't be a name of constant to the correct value, according simple set of rules.
    METHODS conv_values IMPORTING iv_value        TYPE c
                        RETURNING VALUE(ev_value) TYPE ty_const_name.

    "! Generate new class
    METHODS gen_class_new.
    "! Update existing class
    METHODS gen_class_upd.

    METHODS set_domain_name IMPORTING iv_name TYPE domname.         " set name of data element
    METHODS add_fixed_value IMPORTING iv_name TYPE val_single
                                      iv_text TYPE val_text.
    METHODS add_value_translation IMPORTING iv_name TYPE val_single
                                            iv_lang TYPE spras
                                            iv_text TYPE seodescr.

    METHODS check_references IMPORTING iv_value        TYPE ty_const_name
                             RETURNING VALUE(ev_value) TYPE flag.
    METHODS load_reference.
    METHODS get_references IMPORTING iv_value       TYPE ty_const_name
                           CHANGING  VALUE(et_list) TYPE tt_strings.
    METHODS is_domain_restricted IMPORTING iv_value         TYPE domname
                                 RETURNING VALUE(ev_result) TYPE abap_bool.

    DATA mv_lasterror TYPE ty_error.
    METHODS get_last_error RETURNING VALUE(ev_lasterror)  TYPE ty_error.
    METHODS set_error IMPORTING iv_error  TYPE ty_error.

    "--------------------------------------
    " UNDER CONSTRUCTION
    "--------------------------------------
ENDCLASS.                    "lcl_abapclass_generator DEFINITION

***********************************************************************
*       CLASS lcl_domainclass_generator IMPLEMENTATION
***********************************************************************
CLASS lcl_domainclass_generator IMPLEMENTATION.

  METHOD get_instance.
    CREATE OBJECT eo_instance.
  ENDMETHOD.

  METHOD set_class_preffix.
    mv_class_preffix = iv_value.
    RETURN.
  ENDMETHOD.

  METHOD set_class_package.
    mv_package = iv_package.
    RETURN.
  ENDMETHOD.

  METHOD set_class_transport.
    mv_corrnr = iv_request.
    RETURN.
  ENDMETHOD.

  METHOD set_de_name.
    " ???????????????????? ?????? ???????????????? ???????????? ?????? ???????????????? ?????????? ???????????????????????????? ??????????
    DATA lv_name TYPE seoclsname.
    mv_delem = iv_name.

    CONCATENATE mv_class_preffix mv_delem INTO lv_name.
    me->set_class_name( lv_name ).
  ENDMETHOD.                    "set_de_name

  METHOD set_class_name.
    " ???????????????????? ?????? ?????????????????????????? ????????????
    mv_clsname = iv_name.
  ENDMETHOD.                    "set_class_name

  METHOD get_class_name.
    " ?????????????? ?????? ?????????????????????????? ???????????? ???? ?????????????? ??????????????????
    ev_name = mv_clsname.
  ENDMETHOD.

  METHOD set_domain_name.
    " ?????????????????? ?????? ????????????
    mv_domain = iv_name.
  ENDMETHOD.                    "set_domain_name

  METHOD add_fixed_value.
    " ?????????? ?????? ???????????????????? ?? ?????????? ???????????????????????????? ???????????????? ????????????
    DATA lv_type TYPE rs38l_typ.
    DATA lv_name TYPE ty_const_name.
    DATA lv_value TYPE seovalue.
    DATA lo_type TYPE REF TO cl_abap_datadescr.

    " ???????????????????????? ?????? ??????????????????
    lv_name = iv_name.
    lv_name = me->conv_values( lv_name ).
    CONCATENATE mc_const_preffix lv_name INTO lv_name.

    lv_type = mv_delem.   " !???????????????????????????? ??????????

    " ???????????????????????? ???????????????? ?????? ??????????????????
    lo_type ?= cl_abap_datadescr=>describe_by_name( lv_type ).
    CASE lo_type->type_kind.
      WHEN cl_abap_datadescr=>typekind_char.
        CONCATENATE '''' iv_name '''' INTO lv_value.
      WHEN cl_abap_typedescr=>typekind_int OR
           cl_abap_typedescr=>typekind_num.
        WRITE iv_name TO lv_value.
      WHEN cl_abap_typedescr=>typekind_date.
        WRITE iv_name TO lv_value DD/MM/YYYY.
      WHEN OTHERS.
        " !make dump
        ASSERT 1 = 0.
    ENDCASE.

    " ??????????????????
    add_const( iv_name = lv_name
               iv_desc = iv_text
               iv_type = lv_type
               iv_value = lv_value ).
  ENDMETHOD.                    "add_fixed_value

  METHOD add_value_translation.
    DATA lv_name TYPE ty_const_name.

    lv_name = iv_name.
    lv_name = me->conv_values( lv_name ).
    CONCATENATE mc_const_preffix lv_name INTO lv_name.
    READ TABLE mt_const
      WITH TABLE KEY name = lv_name
      ASSIGNING FIELD-SYMBOL(<const>).
    ASSERT sy-subrc = 0.

    DATA ls_trans TYPE ty_const_translation.
    ls_trans-lang = iv_lang.
    ls_trans-desc = iv_text.
    INSERT ls_trans INTO TABLE <const>-trans.
  ENDMETHOD.

  METHOD add_const.
    " ?????????? ?????? ?????????????????????? ?????????? ??????????????????
    DATA wa_const TYPE ty_const.
    wa_const-name = iv_name.
    wa_const-desc = iv_desc.
    wa_const-type = iv_type.
    wa_const-value = iv_value.
    INSERT wa_const INTO TABLE mt_const.
  ENDMETHOD.                    "add_const


  METHOD conv_values.
    " ?????????? ???????????????????????? ???????????????? ???????????? ?? ????????????????, ?????????????? ?????????? ???????? ?????????????? ???????????????? ?? ?????????? ????????????
    ev_value = iv_value.
    IF ev_value EQ space.
      ev_value = 'space'.
    ENDIF.
    IF ev_value CS '*'.
      REPLACE ALL OCCURRENCES OF '*' IN ev_value WITH 'asterisk'.
    ENDIF.
    IF ev_value CS '-'.
      REPLACE ALL OCCURRENCES OF '-' IN ev_value WITH 'minus'.
    ENDIF.
    IF ev_value CS '+'.
      REPLACE ALL OCCURRENCES OF '+' IN ev_value WITH 'plus'.
    ENDIF.
    IF ev_value CS '/'.
      REPLACE ALL OCCURRENCES OF '/' IN ev_value WITH '_'.
    ENDIF.
    IF ev_value CS '\'.
      REPLACE ALL OCCURRENCES OF '\' IN ev_value WITH 'b_'.
    ENDIF.
    IF ev_value CS '$'.
      REPLACE ALL OCCURRENCES OF '$' IN ev_value WITH 'dollar'.
    ENDIF.
    IF ev_value CS space.
      SHIFT ev_value RIGHT DELETING TRAILING space.
      TRANSLATE ev_value USING ' _'.
      SHIFT ev_value LEFT DELETING LEADING '_'.
    ENDIF.
    IF ev_value CS '&'.
      REPLACE ALL OCCURRENCES OF '&' IN ev_value WITH '_'.
    ENDIF.

*    case iv_value.
*      when space.
*        ev_value = 'space'.
*      when '*'.
*        ev_value = 'asterisk'.
*      when '-'.
*        ev_value = 'minus'.
*      when '+'.
*        ev_value = 'plus'.
*      when '/'.
*        ev_value = '_'.
*      when '\'.
*        ev_value = 'b_'.
*      when others.
*        ev_value = iv_value.
*    endcase.

  ENDMETHOD.

  METHOD gen_class.

    DATA ls_dd04v TYPE dd04v.
    DATA ls_dd01v TYPE dd01v.
    DATA lt_dd01v TYPE STANDARD TABLE OF dd01v.
    DATA lt_dd07v TYPE TABLE OF dd07v.
    DATA lt_dd07tv TYPE STANDARD TABLE OF dd07tv.
    FIELD-SYMBOLS <dd07v> TYPE dd07v.
    DATA lt_langu TYPE STANDARD TABLE OF ddlanguage.

    DATA lo_struct_descr TYPE REF TO cl_abap_structdescr.
    DATA lt_field TYPE ddfields.
    FIELD-SYMBOLS <field> TYPE LINE OF ddfields.
    DATA lv_texttable TYPE char128.

    DATA: lv_sqlfields   TYPE char128,
          lv_wherefields TYPE char128.

    DATA lv_msg_txt TYPE char256.

    " FM GET_DTED_FOR_VERSIONS
    CALL FUNCTION 'DDIF_DTEL_GET'
      EXPORTING
        name          = mv_delem
        langu         = sy-langu
      IMPORTING
        dd04v_wa      = ls_dd04v
      EXCEPTIONS
        illegal_input = 1
        OTHERS        = 2.
    CHECK sy-subrc = 0.

    IF ls_dd04v-domname IS INITIAL.
      lv_msg_txt = |Data elem { mv_delem } has no domain, class will be not created!|.
      lcl_list_log=>add_message_text( iv_msgty = 'W'
                                      iv_text  = lv_msg_txt ).
      RETURN.
    ELSEIF me->is_domain_restricted( ls_dd04v-domname ) = abap_true.
      " ?????????????????? ???????????? ???????????????? ?????????????? ?????????? ????????????????, ???????????? ???? ???????????????????????? ?????????? ????????????????????
      " ?????? ?????? ???????????? ?????????????????? ???? ??????????
      lv_msg_txt = |'Domain { ls_dd04v-domname } is restricted, class will be not created!|.
      lcl_list_log=>add_message_text( iv_msgty = 'W'
                                      iv_text  = lv_msg_txt ).
      RETURN.
    ENDIF.

    CALL FUNCTION 'GET_DOMD_FOR_VERSIONS'
      EXPORTING
        domname   = ls_dd04v-domname
      TABLES
        vd01v     = lt_dd01v
        vd07v     = lt_dd07v
        vd07tv    = lt_dd07tv
      EXCEPTIONS
        not_found = 1
        no_mod_dd = 2
        OTHERS    = 3.
    ASSERT sy-subrc = 0.
*    call function 'DDIF_DOMA_GET'
*      exporting
*        name          = ls_dd04v-domname
*        langu         = sy-langu
*      importing
*        dd01v_wa      = ls_dd01v
*      tables
*        dd07v_tab     = lt_dd07v
*      exceptions
*        illegal_input = 1
*        others        = 2.
    me->set_domain_name( ls_dd04v-domname ).
    READ TABLE lt_dd01v INTO ls_dd01v INDEX 1.
    ASSERT sy-subrc = 0.

    IF ls_dd01v-entitytab IS INITIAL.
      "---------------------------------------------------
      " load fixed values enumerated in domain
      LOOP AT lt_dd07v ASSIGNING <dd07v>.
        me->add_fixed_value( iv_name = <dd07v>-domvalue_l
                             iv_text = <dd07v>-ddtext ).

        LOOP AT lt_dd07tv ASSIGNING FIELD-SYMBOL(<dd07tv>)
          WHERE domname = <dd07v>-domname
            AND domvalue_l = <dd07v>-domvalue_l.
          me->add_value_translation( iv_name = <dd07v>-domvalue_l
                                     iv_lang = <dd07tv>-ddlanguage
                                     iv_text = <dd07tv>-ddtext ).
        ENDLOOP.
      ENDLOOP.
    ELSE.
      "---------------------------------------------------
      " load fixed values from table with values

      " get table fields
      lo_struct_descr ?= cl_abap_typedescr=>describe_by_name( ls_dd01v-entitytab ).
      lt_field = lo_struct_descr->get_ddic_field_list( ).
      READ TABLE lt_field WITH KEY domname = ls_dd04v-domname
        ASSIGNING <field>.
      ASSERT sy-subrc = 0.

      " get text table for table with values of domain
      SELECT tabname
        INTO lv_texttable UP TO 1 ROWS
        FROM dd08vv
        WHERE checktable = ls_dd01v-entitytab
          AND as4local = mc_as4local_active
          AND fieldname = <field>-fieldname
          AND frkart = 'TEXT'
        ORDER BY primpos.
      ENDSELECT.

      IF lv_texttable IS INITIAL.
        lv_msg_txt = |Can't find text table for domain value table { ls_dd01v-entitytab } and field { <field>-fieldname }|.
        lcl_list_log=>add_message_text( iv_msgty = 'E'
                                        iv_text  = lv_msg_txt ).

        RETURN.
      ENDIF.
      CONCATENATE <field>-fieldname 'AS domvalue_l ' INTO lv_sqlfields SEPARATED BY space.
      lo_struct_descr ?= cl_abap_typedescr=>describe_by_name( lv_texttable ).
      lt_field = lo_struct_descr->get_ddic_field_list( ).
      READ TABLE lt_field WITH KEY inttype = 'C'
                                   keyflag = abap_false
        ASSIGNING <field>.
      ASSERT sy-subrc = 0.
      CONCATENATE lv_sqlfields <field>-fieldname 'as ddtext' INTO lv_sqlfields SEPARATED BY space.
      READ TABLE lt_field WITH KEY datatype = 'LANG'
        ASSIGNING <field>.
      ASSERT sy-subrc = 0.
      CONCATENATE <field>-fieldname ' = ' '''' me->mc_def_lang '''' INTO lv_wherefields.

      " get description from text table for domain
      SELECT (lv_sqlfields)
        INTO CORRESPONDING FIELDS OF TABLE lt_dd07v
        FROM (lv_texttable)
        WHERE (lv_wherefields).

      LOOP AT lt_dd07v ASSIGNING <dd07v>.
        me->add_fixed_value( iv_name = <dd07v>-domvalue_l
                             iv_text = <dd07v>-ddtext ).
*        me->add_value_translation( iv_name = <dd07v>-domvalue_l
*                                   iv_lang = <dd07tv>-spras
*                                   iv_text = <dd07tv>-ddtext ).
      ENDLOOP.

    ENDIF.

    " Create class only, if we have any fixed value, in other cases don't create it
    IF mt_const[] IS INITIAL.
      lv_msg_txt = |Domain { mv_domain } has no fixed values, class will be not created!|.
      lcl_list_log=>add_message_text( iv_msgty = 'W'
                                      iv_text  = lv_msg_txt ).
      RETURN.
*      raise resumable exception type lcx_domainclass_generator
*        exporting
*          textid = lcx_domainclass_generator=>empty_constants
*          attr1  = 'Domain'
*          attr2  = mv_domain
*          attr3  = 'has no fixed values, class will be not created!'.
    ENDIF.

    " Generate/Update domain class
    DATA ls_clskey TYPE seoclskey.
    ls_clskey-clsname = mv_clsname.
    CALL FUNCTION 'SEO_CLASS_EXISTENCE_CHECK'
      EXPORTING
        clskey        = ls_clskey
      EXCEPTIONS
        not_specified = 1
        not_existing  = 2
        is_interface  = 3
        no_text       = 4
        inconsistent  = 5
        OTHERS        = 6.
    IF sy-subrc <> 0.
      me->gen_class_new( ).
    ELSE.
      me->gen_class_upd( ).
    ENDIF.

  ENDMETHOD.                    "gen_class

  METHOD gen_class_new.
    " Generate new class for data element
    DATA: wa_vseoclass  TYPE                   vseoclass,
          wa_vseoextend TYPE                   vseoextend,
          wa_vseoattrib TYPE                   vseoattrib,
          lt_attributes TYPE                   seo_attributes,
          wa_cmp_descr  TYPE                   seocompotx,
          lt_cmp_descr  TYPE STANDARD TABLE OF seocompotx.

*   CLASS DEFINITION :
    DATA lv_descript TYPE seodescr.
    DATA lv_author TYPE sy-uname.

    lv_author = sy-uname.
    lv_descript = me->mc_class_descrip.
    REPLACE '%domain%' IN lv_descript WITH mv_domain.
    wa_vseoclass-clsname = mv_clsname.
    wa_vseoclass-state = seoc_state_implemented.
    wa_vseoclass-exposure = seoc_exposure_public.
    wa_vseoclass-langu = mc_def_lang.
    wa_vseoclass-descript = lv_descript.                    "#EC NOTEXT
    wa_vseoclass-clsccincl = abap_true.
    wa_vseoclass-unicode = abap_true.
    wa_vseoclass-author = lv_author.

*   ATTRIBUTES :
    FIELD-SYMBOLS <const> TYPE ty_const.
    DELETE ADJACENT DUPLICATES FROM mt_const.
    LOOP AT mt_const ASSIGNING <const>.
      CLEAR wa_vseoattrib.
      wa_vseoattrib-clsname = mv_clsname.
      wa_vseoattrib-cmpname = <const>-name.
      wa_vseoattrib-descript = <const>-desc.                "#EC NOTEXT
      wa_vseoattrib-state =  seoc_state_implemented.
      wa_vseoattrib-exposure = seoc_exposure_public.
      wa_vseoattrib-attdecltyp = seoo_attdecltyp_constants.
      wa_vseoattrib-typtype = seoo_typtype_type.
      wa_vseoattrib-type = <const>-type.
      wa_vseoattrib-attvalue = <const>-value.
      APPEND wa_vseoattrib TO lt_attributes.

*      Translations for descriptions :
      LOOP AT <const>-trans ASSIGNING FIELD-SYMBOL(<trans>).
        wa_cmp_descr-clsname = mv_clsname.
        wa_cmp_descr-cmpname = <const>-name.
        wa_cmp_descr-langu = <trans>-lang.
        wa_cmp_descr-descript = <trans>-desc.
        APPEND wa_cmp_descr TO lt_cmp_descr.
      ENDLOOP.

    ENDLOOP.
    DELETE ADJACENT DUPLICATES FROM lt_attributes.

*   GENERATION
    CALL FUNCTION 'SEO_CLASS_CREATE_COMPLETE'
      EXPORTING
*       corrnr                 = me->mv_corrnr
        devclass               = me->mv_package
        version                = seoc_version_active
*       authority_check        = seox_false
*       overwrite              = seox_true
*       suppress_method_generation = seox_false
*       genflag                = seox_false
      TABLES
        component_descriptions = lt_cmp_descr
      CHANGING
        class                  = wa_vseoclass
        inheritance            = wa_vseoextend
        attributes             = lt_attributes
      EXCEPTIONS
        existing               = 1
        is_interface           = 2
        db_error               = 3
        component_error        = 4
        no_access              = 5
        other                  = 6
        OTHERS                 = 7.
    ASSERT sy-subrc = 0.

    IF mv_corrnr IS NOT INITIAL.
      " insert generated class in the transport
      DATA ls_key TYPE ko200.
      ls_key-pgmid = 'R3TR'.
      ls_key-object = 'CLAS'.
      ls_key-obj_name = mv_clsname.
      CALL FUNCTION 'TR_OBJECT_INSERT'
        EXPORTING
          wi_order                = me->mv_corrnr
          wi_ko200                = ls_key
        EXCEPTIONS
          cancel_edit_other_error = 1
          show_only_other_error   = 2
          OTHERS                  = 3.
      ASSERT sy-subrc = 0.
    ENDIF.

  ENDMETHOD.                    "gen_class_new

* Update exists class
  METHOD gen_class_upd.

    DATA lv_msg_txt TYPE char256.

    DATA: wa_vseoclass       TYPE vseoclass,
          wa_attributes      TYPE seoo_attribute_r,
          lt_attributes      TYPE seoo_attributes_r,
          lt_attributes_flat TYPE seoo_attributes_flat.
    FIELD-SYMBOLS <attributes_flat> TYPE seoattflt.

    DATA: wa_cmp_descr TYPE                   seocompotx,
          lt_cmp_descr TYPE STANDARD TABLE OF seocompotx.

    DATA: lv_version       TYPE seoversion VALUE seoc_version_active,
          lv_inactive_flag TYPE seox_boolean,
          ls_clskey        TYPE seoclskey,
          lt_clskey        TYPE seoc_class_keys.

    ls_clskey-clsname = mv_clsname.
    APPEND ls_clskey TO lt_clskey.

    " get current version of class
    CALL FUNCTION 'SEO_CLASS_EXISTENCE_CHECK'
      EXPORTING
        clskey        = ls_clskey
      IMPORTING
        not_active    = lv_inactive_flag
      EXCEPTIONS
        not_specified = 1
        not_existing  = 2
        is_interface  = 3
        no_text       = 4
        inconsistent  = 5
        OTHERS        = 6.
    ASSERT sy-subrc = 0.
    IF lv_inactive_flag = seox_true.
      lv_version = seoc_version_inactive.
    ELSE.
      lv_version = seoc_version_active.
    ENDIF.

    CALL FUNCTION 'SEO_CLASS_TYPEINFO_BY_VIS'
      EXPORTING
        clskey       = ls_clskey
        version      = lv_version
      IMPORTING
        class        = wa_vseoclass
      EXCEPTIONS
        not_existing = 1
        is_interface = 2
        model_only   = 3
        OTHERS       = 4.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.

    " check that it is allowed to regenerate class
    IF wa_vseoclass-descript(7) = mc_tag_modif.
      " Current class was created manually and regeneration are restricted
      " No need to update it. Exiting!
      lv_msg_txt = |Class { wa_vseoclass-clsname } was restricted from regenerations!|.
      lcl_list_log=>add_message_text( iv_msgty = 'E' iv_text = lv_msg_txt ).
      RETURN.
    ENDIF.

    CALL FUNCTION 'SEO_CLIF_ATTRIBUTES_FLAT'
      EXPORTING
        cifkey       = ls_clskey
        version      = lv_version
*       STATE        = '1'
      IMPORTING
        attributes   = lt_attributes_flat
      EXCEPTIONS
        not_existing = 1
        model_only   = 2
        other        = 3
        OTHERS       = 4.
    IF sy-subrc = 0.

      lv_version = seoc_version_active.
      DELETE ADJACENT DUPLICATES FROM mt_const COMPARING name.

      LOOP AT lt_attributes_flat ASSIGNING <attributes_flat>
        WHERE attdecltyp = seoo_attdecltyp_constants.

        MOVE-CORRESPONDING <attributes_flat> TO wa_attributes.
        wa_attributes-clsname = <attributes_flat>-cifname.
        wa_attributes-cmpname = <attributes_flat>-attname.
        APPEND wa_attributes TO lt_attributes.

        " !BUG! place
        " ???????? ???? ?????????????????? ?????????????? ???????? ????????????, ?????????? ?????????? ???????????? ???????????????????????? ?? ???????? ?????????????? ?????????????????? ???? ????????????
        READ TABLE mt_const
          WITH TABLE KEY name = <attributes_flat>-attname
          TRANSPORTING NO FIELDS.
        IF sy-subrc <> 0.
          IF me->check_references( <attributes_flat>-attname ) = abap_true.
            lv_version = seoc_version_inactive.

            " ???????????????? ?????????? ?????????????? ?? ?????????????? ???????????????????????? ?????????????????? ???????????????? ????????????
            DATA lt_reference TYPE tt_strings.
            me->get_references( EXPORTING iv_value = <attributes_flat>-attname
                                CHANGING  et_list = lt_reference ).
            lv_msg_txt = 'Deleted domain value %domain-value% used in follow includes:'.
            REPLACE '%domain-value%' IN lv_msg_txt WITH <attributes_flat>-attname.
            lcl_list_log=>add_message_text( iv_msgty = 'E' iv_text = lv_msg_txt ).
            LOOP AT lt_reference ASSIGNING FIELD-SYMBOL(<fs>).
              lcl_list_log=>add_message_text( iv_msgty = 'E' iv_text = <fs> ).
            ENDLOOP.

          ENDIF.
        ENDIF.
      ENDLOOP.

      IF lt_attributes IS NOT INITIAL.
        CALL FUNCTION 'SEO_CLASS_DELETE_COMPONENTS'
          EXPORTING
            "corrnr             = me->mv_corrnr
            version            = seoc_version_active
            clskey             = ls_clskey
            "SUPPRESS_INDEX_UPDATE       = SEOX_FALSE
          CHANGING
            attributes         = lt_attributes
          EXCEPTIONS
            class_not_existing = 1
            db_error           = 2
            component_error    = 3
            no_access          = 4
            other              = 5
            OTHERS             = 6.
        ASSERT sy-subrc = 0.

*        call function 'SEO_CLASS_ACTIVATE'
*          exporting
*            clskeys       = lt_clskey
*          exceptions
*            not_specified = 1
*            not_existing  = 2
*            inconsistent  = 3
*            others        = 4.
*        assert sy-subrc = 0.
      ENDIF.

    ENDIF.

    CLEAR lt_attributes.

    DATA wa_vseoattrib TYPE vseoattrib.
    FIELD-SYMBOLS <const> TYPE ty_const.
    LOOP AT mt_const ASSIGNING <const>.
      CLEAR wa_vseoattrib.
      wa_vseoattrib-clsname = mv_clsname.
      wa_vseoattrib-cmpname = <const>-name.
      wa_vseoattrib-descript = <const>-desc.                "#EC NOTEXT
      wa_vseoattrib-state =  seoc_state_implemented.
      wa_vseoattrib-exposure = seoc_exposure_public.
      wa_vseoattrib-attdecltyp = seoo_attdecltyp_constants.
      wa_vseoattrib-typtype = seoo_typtype_type.
      wa_vseoattrib-type = <const>-type.
      wa_vseoattrib-attvalue = <const>-value.
      APPEND wa_vseoattrib TO lt_attributes.

*     Translations for descriptions :
      LOOP AT <const>-trans ASSIGNING FIELD-SYMBOL(<trans>).
        wa_cmp_descr-clsname = mv_clsname.
        wa_cmp_descr-cmpname = <const>-name.
        wa_cmp_descr-langu = <trans>-lang.
        wa_cmp_descr-descript = <trans>-desc.
        APPEND wa_cmp_descr TO lt_cmp_descr.
      ENDLOOP.

    ENDLOOP.

    CALL FUNCTION 'SEO_CLASS_ADD_COMPONENTS'
      EXPORTING
        clskey                 = ls_clskey
        corrnr                 = me->mv_corrnr
        version                = seoc_version_active
        "SUPPRESS_INDEX_UPDATE           = SEOX_FALSE
      TABLES
        component_descriptions = lt_cmp_descr
      CHANGING
        attributes             = lt_attributes
      EXCEPTIONS
        class_not_existing     = 1
        db_error               = 2
        component_error        = 3
        no_access              = 4
        other                  = 5
        OTHERS                 = 6.
    ASSERT sy-subrc = 0.

*    call function 'SEO_CLASS_ACTIVATE'
*      exporting
*        clskeys       = lt_clskey
*      exceptions
*        not_specified = 1
*        not_existing  = 2
*        inconsistent  = 3
*        others        = 4.
*    assert sy-subrc = 0.

  ENDMETHOD.                    "gen_class_upd

  METHOD check_references.
    " check, that exists any abap program, that has reference to current fixed domain value

    IF mv_loaded_class <> me->get_class_name( ).
      me->load_reference( ).
    ENDIF.

    READ TABLE mt_reference
        WITH KEY name = iv_value
        BINARY SEARCH
        TRANSPORTING NO FIELDS.
    IF sy-subrc = 0.
      ev_value = abap_true.
    ELSE.
      ev_value = abap_false.
    ENDIF.

  ENDMETHOD.

  METHOD load_reference.
    " load in memory all includes, which contain reference to current domain value
    CONSTANTS lc_escape TYPE c VALUE '\'.
    CONSTANTS lc_separator TYPE c VALUE ':'.
    DATA lv_name TYPE eu_lname.
    DATA lv_value TYPE ty_const_name.
    FIELD-SYMBOLS <reference> TYPE LINE OF tt_reference.

    lv_name = me->get_class_name( ).
    CONCATENATE lv_name lc_escape me->mc_otype_domattr lc_separator '%' INTO lv_name.
    SELECT name include
        INTO TABLE me->mt_reference
        FROM wbcrossgt
        WHERE otype = me->mc_otype_domattr
          AND name LIKE lv_name.
    IF sy-subrc = 0.
      LOOP AT me->mt_reference ASSIGNING <reference>.
        SPLIT <reference>-name AT lc_separator INTO DATA(lv_dummy) <reference>-name.
      ENDLOOP.
    ELSE.
      CLEAR me->mt_reference.
    ENDIF.

    mv_loaded_class = me->get_class_name( ).
  ENDMETHOD.

  METHOD get_references.
    " return all includes, which contain reference to current domain value

    READ TABLE mt_reference
        WITH KEY name = iv_value
        BINARY SEARCH
        TRANSPORTING NO FIELDS.
    LOOP AT mt_reference
      ASSIGNING FIELD-SYMBOL(<fs>)
      FROM sy-index
      WHERE name = iv_value.
      APPEND <fs> TO et_list.
    ENDLOOP.

  ENDMETHOD.

  METHOD is_domain_restricted.
    " Some of domains has problems while generation of class
    " so there no necesary to generate class with problems
    ev_result = abap_false.
    IF   iv_value = 'FUNCNAME'
      OR iv_value = 'ZICM_INT_TAB_NAME'.
      ev_result = abap_true.
    ENDIF.

  ENDMETHOD.

  METHOD get_last_error.
    ev_lasterror = mv_lasterror.
  ENDMETHOD.

  METHOD set_error.
    mv_lasterror = iv_error.
  ENDMETHOD.

ENDCLASS.                    "lcl_domainclass_generator IMPLEMENTATION


***********************************************************************
* Selection screen
***********************************************************************
SELECTION-SCREEN BEGIN OF BLOCK sel01 WITH FRAME TITLE text-t01.

DATA lv_ddobjname TYPE rollname.
SELECT-OPTIONS s_dtelnm FOR lv_ddobjname DEFAULT 'ZICM_*'.

SELECTION-SCREEN END OF BLOCK sel01.

SELECTION-SCREEN BEGIN OF BLOCK s02 WITH FRAME TITLE text-t02.
PARAMETERS: p_clpref  TYPE string DEFAULT 'ZDDIC_CL_',
            p_packag  TYPE devclass DEFAULT 'ZICM_APPL_DDIC',
            p_transp  TYPE trkorr DEFAULT space.
SELECTION-SCREEN END OF BLOCK s02.

AT SELECTION-SCREEN ON VALUE-REQUEST FOR p_transp.
  PERFORM f4if_transport_request CHANGING p_transp.

***********************************************************************
* Main program
***********************************************************************
START-OF-SELECTION.

  DATA lt_dtel TYPE STANDARD TABLE OF rollname.

  DATA lv_msg_txt TYPE char256.

  DATA lo_clgen TYPE REF TO lcl_domainclass_generator.
*  data lcx_clgen type ref to lcx_domainclass_generator.

  SELECT rollname
    INTO TABLE lt_dtel
    FROM dd04l
    WHERE rollname IN s_dtelnm
      AND as4local = lcl_domainclass_generator=>mc_as4local_active.

  " set log level
  IF sy-batch = abap_true.
    " in background mode log only errors (to reduce logs size)
    lcl_list_log=>set_log_level( iv_level = 'E' ).
  ELSE.
    " in dialog mode log all messages
    lcl_list_log=>set_log_level( iv_level = 'I' ).
  ENDIF.

  " generate class for each data element
  LOOP AT lt_dtel ASSIGNING FIELD-SYMBOL(<dtel>).

    lo_clgen = lcl_domainclass_generator=>get_instance( ).

    lo_clgen->set_class_preffix( p_clpref ).
    lo_clgen->set_class_package( p_packag ).
    lo_clgen->set_class_transport( p_transp ).

    lo_clgen->set_de_name( <dtel> ).
    TRY.
        lo_clgen->gen_class( ).

        lv_msg_txt = 'Class %class% for data elem %delem% - processed succesfull!'.
        REPLACE '%class%' IN lv_msg_txt WITH lo_clgen->get_class_name( ).
        REPLACE '%delem%' IN lv_msg_txt WITH <dtel>.
        lcl_list_log=>add_message_text( iv_msgty = 'I' iv_text = lv_msg_txt ).
*      catch lcx_domainclass_generator into lcx_clgen.
*        write: / 'Class ', lo_clgen->get_class_name( ), 'for data elem ', <dtel>, ' - was finished with errors!'.
    ENDTRY.
    CLEAR lo_clgen.

  ENDLOOP.

  EXIT.

***********************************************************************
* FORMS
***********************************************************************
FORM  f4if_transport_request CHANGING cv_transp TYPE trkorr.
  DATA: ls_request   TYPE trwbo_request_header,
        ls_selection TYPE trwbo_selection.

  ls_selection-reqfunctions = 'FTCOK'.
  ls_selection-reqstatus    = 'DL'. " not released

  CALL FUNCTION 'TR_PRESENT_REQUESTS_SEL_POPUP'
    EXPORTING
      iv_organizer_type   = 'T'
      is_selection        = ls_selection
      iv_username         = sy-uname
    IMPORTING
      es_selected_request = ls_request
    EXCEPTIONS
      OTHERS              = 1.

  IF sy-subrc = 0.
    IF ls_request-trkorr <> space.
      cv_transp = ls_request-trkorr.
    ENDIF.
  ENDIF.

ENDFORM.
