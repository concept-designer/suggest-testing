#Обёртка для работы с API сервиса kladr-api.ru
package KladrAPI;
{
  use strict;
  use utf8;
  use LWP::UserAgent;
  use JSON;
  use Encode;
  
  #Конструирует объект
  sub new( $$ )
  {
    my ( $class, $Token ) = @_;
    
    my $self = 
    { 
      user_agent => LWP::UserAgent->new( agent => "Mozilla/5.0 (Windows NT 6.1; WOW64; rv:51.0) Gecko/20100101 Firefox/51.0", timeout => 600, keep_alive => 10 )
    };

    bless( $self, $class );

    return $self;    
  }
  
  #Отсылает HTTP-запрос сервису для получения подсказок по заданному префиксу
  #Должен вернуть объектную обёртку поверх JSON-ответа
  sub RequestSuggestions( $$ )
  {
    my ( $self, $Prefix ) = @_;
    
    my $Response = $self->{ user_agent }->get( "http://kladr-api.ru/api.php?oneString=1&limit=10&query=$Prefix&" );
    
    my $Result = undef;
    
    if( defined($Response) && $Response->is_success() )
    {
      $Result = from_json( Encode::decode( "utf8", $Response->content ) );
      
      #Если сервис не вернул подсказки, возвращаем undef
      if( defined( $Result ) && !exists( $Result->{result} ) )
      {
        $Result = undef;
      }
    }
    
    return $Result;
  }
  
  #Ищет среди возвращённых сервисом подсказок целевую
  sub FindPrediction( $$$$$ )
  {
    my ( $self, $Test, $Suggestions, $Stage, $LimitTopN ) = @_;
    
    my $Result = "";
    
    foreach my $Value ( @{ $Suggestions->{result} } )
    {
      #Сравниваем подсказку с целевым результатом, если совпала, значит сервис сделал правильное предсказание
      if( $self->CompareTestWithSuggestion( $Test, $Value->{id}, $Stage ) == 1 )
      {
        $Result = $Value->{fullName};
        last;
      }
      $LimitTopN --;
      last if( $LimitTopN == 0 );
    }
    
    return $Result;
  }
  
  #Сравнивает полученную от сервиса подсказку с целевым значением
  #Данный сервис возвращает коды КЛАДР, поэтому реально сравниваем целевой код с полученным
  sub CompareTestWithSuggestion( $$$ )
  {
    my ( $self, $Test, $KLADR_ID, $Stage ) = @_;
    
    my $RetVal = 0;
    
    if( $Stage eq "city" )
    {
      if( $Test->{city_kladr} ne "" )
      {
        #Если код КЛАДР содержит информацию о доме, отрезаем её
        $KLADR_ID = substr( $KLADR_ID, 0, length( $Test->{city_kladr} ) ) if( length( $KLADR_ID  ) > length( $Test->{city_kladr} ) );
        
        $RetVal = ( $Test->{city_kladr} eq $KLADR_ID ? 1 : 0 );
      }
      else
      {
        #Если код КЛАДР содержит информацию о доме, отрезаем её
        $KLADR_ID = substr( $KLADR_ID, 0, length( $Test->{reg_kladr} ) ) if( length( $KLADR_ID  ) > length( $Test->{reg_kladr} ) );
        
        $RetVal = ( $Test->{reg_kladr} eq $KLADR_ID ? 1 : 0 );
      }
    }
    elsif( $Stage eq "street" )
    {
      #Если код КЛАДР содержит информацию о доме, отрезаем её
      if( length( $KLADR_ID  ) > length( $Test->{street_kladr} ) )
      {
        $KLADR_ID = substr( $KLADR_ID, 0, length( $Test->{street_kladr} ) );
      }
      
      $RetVal = ( $Test->{street_kladr} eq $KLADR_ID ? 1 : 0 );
    }
    
    return $RetVal;
  }
  
  #Возвращает массив префиксов для названия города
  # Метод добавлен чисто для проверки, как себя будет вести данный сервис, если добавить тип города
  # - Test - исходный тест, откуда берёт название города
  sub BuildCityPrefixes_JustForTests( $$ )
  {
    my ( $self, $Test ) = @_;
    
    my $Result = [];
      
    my $TestName = $Test->{city};
    $TestName = $Test->{reg} if( $TestName eq "" && $Test->{reg_type} eq "г" );
    
    my $TestType = $Test->{city_type};
    $TestType = $Test->{reg_type} if( $TestType eq "" && $Test->{reg_type} eq "г" );
  
    my $Prefix = "";
    
    #сначала подставляем тип города, без него данный сервис города подсказывает плохо
    foreach my $Letter ( split( "", $TestType ) )
    {
      $Prefix .= $Letter;
      push @$Result, $Prefix;
    }
    
    $Prefix .= " ";
    
    #теперь подставляем буквы самого города
    foreach my $Letter ( split( "", $TestName ) )
    {
      $Prefix .= $Letter;
      push @$Result, $Prefix;
    }
    
    #Добавляем пробел к последнему префиксу, чтобы сообщить, что это полное имя города
    push @$Result, $Prefix." ";
    
    return $Result;
  }
  
  #Возвращает массив префиксов для заданной строки
  # - PredictedCity - правильно предложенный сервисом город в одной из предыдущих подсказок,
  #   он вставляется в начало каждого формируемого префикса
  # - Test - тест, откуда вытаскиваются данные для генерации префиксов
  sub BuildStreetPrefixes( $$$ )
  {
    my ( $self, $PredictedCity, $Test ) = @_;
    
    my $Result = [];
    
    my $Prefix = $PredictedCity.", ";
    
    #сначала подставляем тип улицы, без него данный сервис улицы не умеет подсказывать
    foreach my $Letter ( split( "", $Test->{street_type} ) )
    {
      $Prefix .= $Letter;
      push @$Result, $Prefix;
    }
    
    $Prefix .= " ";
    
    #теперь подставляем буквы самой улиц
    foreach my $Letter ( split( "", $Test->{street} ) )
    {
      $Prefix .= $Letter;
      push @$Result, $Prefix;
    }
    
    #Добавляем пробел к последнему префиксу, чтобы сообщить, что это полное имя улицы
    push @$Result, $Prefix." ";
    
    return $Result;
  }
};
1;