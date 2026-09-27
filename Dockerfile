FROM erlang:28-alpine

WORKDIR /app
COPY src ./src
COPY static ./static

RUN mkdir -p _build/ebin \
    && erlc -Werror -o _build/ebin src/*.erl \
    && cp src/telecomerl.app.src _build/ebin/telecomerl.app

ENV TELECOM_STATIC_DIR=/app/static
EXPOSE 8080

CMD ["erl", "-pa", "_build/ebin", "-noshell", "-eval", "telecomerl:start(), receive stop -> ok end."]