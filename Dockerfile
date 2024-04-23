FROM arm64v8/ubuntu:20.04
# FROM alpine:3.17

WORKDIR /run

COPY ./build/op-reth ./op-reth

RUN chmod +x ./op-reth

ENV PATH="/run:${PATH}"

CMD /run/op-reth