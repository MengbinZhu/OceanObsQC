MODULE obs_reader_bufr_mod
  USE obs_reader_mod
  USE profile_mod
  USE vec_profile_mod
  USE gsw_mod_toolbox

  IMPLICIT NONE
  PRIVATE

  !=============================================================================
  !>
  !-----------------------------------------------------------------------------
  TYPE, EXTENDS(obs_reader), PUBLIC :: obs_reader_bufr
   CONTAINS
     PROCEDURE, NOPASS :: name => bufr_get_name
     PROCEDURE, NOPASS :: init => bufr_init
     PROCEDURE, NOPASS :: obs_read => bufr_read
  END TYPE obs_reader_bufr
  !=============================================================================


  REAL, PARAMETER :: BUFR_UNDEF = 9.9e9


CONTAINS


  !=============================================================================
  !>
  !-----------------------------------------------------------------------------
  FUNCTION bufr_get_name() RESULT(name)
    CHARACTER(:), ALLOCATABLE :: name
    name = "BUFR"
  END FUNCTION bufr_get_name
  !=============================================================================



  !=============================================================================
  !>
  !-----------------------------------------------------------------------------
  SUBROUTINE bufr_init(nmlfile)
    INTEGER, INTENT(in) :: nmlfile

    ! TODO, process namelist options
  END SUBROUTINE bufr_init
  !=============================================================================


  !=============================================================================
  !>
  !-----------------------------------------------------------------------------
  SUBROUTINE bufr_read(filename, obs)
    CHARACTER(len=*),  INTENT(in)    :: filename
    TYPE(vec_profile), INTENT(inout) :: obs

    LOGICAL :: valid
    TYPE(profile) :: ob
    INTEGER :: file, idate, iret
    CHARACTER*8 c1

    ! make sure input file exists
    INQUIRE(file=filename, exist=valid)
    IF(.NOT. valid) THEN
       PRINT *, "input file not found: ", TRIM(filename)
       STOP 1
    END IF

    !open file
    file=90
    OPEN(unit=file, file=filename)
    CALL openbf(file,'IN',file)
    CALL datelen(10)

    ! process each profile
    iret = 0
    DO
       CALL readmg(file, c1, idate, iret)
       IF (iret /= 0) EXIT
       DO
          CALL readsb(file, iret)
          IF (iret /= 0) EXIT

          ! read in the profiles, in a way depending on the profile type
          valid = .FALSE.
          IF (c1 == "NC031001" .OR. &
               c1 == "NC031004" ) THEN
             CALL process_bathytesac(file, ob, valid)
             ob%plat = PLAT_BATHY
          ELSE IF (&
               c1 == "NC031002" .OR. &
               c1 == "NC031006" ) THEN
             CALL process_bathytesac(file, ob, valid)
             ob%plat = PLAT_TESAC
          ELSE IF (&
               c1 == "NC001002" .OR. &
               c1 == "DBUOY" ) THEN
             CALL process_bathytesac(file, ob, valid)
             ob%plat = PLAT_BUOY
          ELSE IF(c1 == "NC031005") THEN
             CALL process_float(file, ob, valid)
             ob%plat = PLAT_FLOAT
          ELSE
             PRINT *, "WARN: unknown ob type: ", c1
             STOP 1
          END IF

          ! ignore if not data not valid
          IF (.NOT. valid) CYCLE

          ! convert from K to C
          WHERE(ob%temp < PROF_UNDEF) ob%temp = ob%temp - 273.15

          ! valid ob found, save to list
          CALL obs%push_back(ob)

       END DO
    END DO

    ! all done cleanup
    CALL closbf(file)
    CLOSE(file)
  END SUBROUTINE bufr_read
  !=============================================================================



  !=============================================================================
  !>
  !-----------------------------------------------------------------------------
  SUBROUTINE process_bathytesac(file, ob, valid)
    INTEGER, INTENT(in) :: file
    TYPE(profile), INTENT(out) :: ob
    LOGICAL, INTENT(out) :: valid

    INTEGER :: nlv, i
    INTEGER, PARAMETER :: MXMN=10, MXLV=1000
    REAL*8  r8(MXMN, MXLV)

    CHARACTER str*(8), str2*(8)
    EQUIVALENCE (r8, str)

    valid = .FALSE.

    ! year, month, day
    CALL UFBINT(file, r8, MXMN, MXLV, nlv, 'YEAR MNTH DAYS')
    ob%date = r8(1,1)*10000 + r8(2,1)*100 + r8(3,1)

    ! hour of day (fractional)
    CALL UFBINT(file, r8, MXMN, MXLV, nlv, 'HOUR MINU')
    ob%hour = r8(1,1) + r8(2,1) / 60.0

    ! platform callsign
    CALL ufbint(file, r8, MXMN, MXLV, nlv, 'RPID')
    ob%id = str

    ! lat/lon
    CALL ufbint(file, r8, MXMN, MXLV, nlv, 'CLATH CLONH')
    IF(nlv == 0) THEN
       ! try to find the low res lat/lon instead
       CALL ufbint(file, r8, MXMN, MXLV, nlv, 'CLAT CLON')
    END IF
    ob%lat = r8(1,1)
    ob%lon = r8(2,1)


    ! depth, temperature, salinity
    CALL ufbrep(file, r8, MXMN, MXLV, nlv, 'DBSS STMP SALN')
    IF(nlv==0) THEN
       ! no levels found... keep this profile in case we want the buoy position
       ! info at some point
       ALLOCATE(ob%depth(0), ob%temp(0), ob%salt(0))
       RETURN
    END  IF

    ALLOCATE(ob%depth(nlv))
    ALLOCATE(ob%temp(nlv))
    ALLOCATE(ob%salt(nlv))
    ob%depth = r8(1,1:nlv)
    ob%temp  = r8(2,1:nlv)
    ob%salt  = r8(3,1:nlv)

    ! mark undefined values as undefined
    WHERE (ob%depth > BUFR_UNDEF) ob%depth = PROF_UNDEF
    WHERE (ob%temp > BUFR_UNDEF) ob%temp = PROF_UNDEF
    WHERE (ob%salt > BUFR_UNDEF) ob%salt = PROF_UNDEF

    ! all done
    valid = .TRUE.

  END SUBROUTINE process_bathytesac
  !=============================================================================



  !=============================================================================
  !>
  !-----------------------------------------------------------------------------
  SUBROUTINE process_float(file, ob, valid)
    INTEGER, INTENT(in) :: file
    TYPE(profile), INTENT(out) :: ob
    LOGICAL, INTENT(out) :: valid

    INTEGER :: nlv, i
    INTEGER, PARAMETER :: MXMN=10, MXLV=1000
    REAL*8  r8(MXMN, MXLV)

    CHARACTER str*(8), str2*(8)
    EQUIVALENCE (r8, str)


    ! year, month, day
    CALL UFBSEQ(file, r8, MXMN, MXLV, nlv, 'YYMMDD')
    ob%date = r8(1,1)*10000 + r8(2,1)*100 + r8(3,1)

    ! hour of day(fractional)
    CALL UFBSEQ(file, r8, MXMN, MXLV, nlv, 'HHMM')
    ob%hour = r8(1,1) + r8(2,1) / 60.0

    ! callsign
    CALL ufbint(file, r8, MXMN, MXLV, nlv, 'WMOP')
    IF( r8(1,1) > 9999999) THEN
       PRINT *, "ERROR: float with id greater than 7 characers found"
       STOP
    END IF
    WRITE (ob%id, '(I8)') INT(r8(1,1))

    ! lat/lon
    CALL ufbseq(file, r8, MXMN, MXLV, nlv, 'LTLONH')
    ob%lat = r8(1,1)
    ob%lon = r8(2,1)

    ! pressure, temperature, salinity
    CALL ufbrep(file, r8, MXMN, MXLV, nlv, 'WPRES SSTH SALNH')
    IF(nlv==0) THEN
       !PRINT *, "ERROR: no levels found"
       RETURN
    END  IF
    ALLOCATE(ob%depth(nlv))
    ALLOCATE(ob%temp(nlv))
    ALLOCATE(ob%salt(nlv))
    ob%depth = r8(1,1:nlv)
    ob%temp  = r8(2,1:nlv)
    ob%salt  = r8(3,1:nlv)

    ! mark undefined values as undefined
    WHERE (ob%depth > BUFR_UNDEF) ob%depth = PROF_UNDEF
    WHERE (ob%temp > BUFR_UNDEF) ob%temp = PROF_UNDEF
    WHERE (ob%salt > BUFR_UNDEF) ob%salt = PROF_UNDEF

    ! convert pressure (pascal) to depth (meters)
    WHERE (ob%depth < BUFR_UNDEF) &
         ob%depth = -gsw_z_from_p(r8(1,1:nlv)/10000, ob%lat)

    ! all done
    valid=.TRUE.

  END SUBROUTINE process_float
  !=============================================================================

END MODULE obs_reader_bufr_mod
