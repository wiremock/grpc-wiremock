FROM gradle:8.0.2-jdk17-alpine as cache
RUN mkdir -p /home/gradle/cache_home
RUN mkdir -p /proto
RUN touch /proto/any.proto
ENV GRADLE_USER_HOME /home/gradle/cache_home
COPY build.gradle /home/gradle/java-code/
COPY gradle.properties /home/gradle/java-code/
WORKDIR /home/gradle/java-code
RUN gradle build -i --no-daemon || return 0

FROM gradle:8.0.2-jdk17-alpine as runner
RUN apk update && apk add gcompat # alpine uses musl while protoc binaries are compiled against glibc. gcompat fixes that.
COPY --from=cache /home/gradle/cache_home /home/gradle/.gradle
COPY . /usr/src/java-code/
WORKDIR /usr/src/java-code
EXPOSE 8888 50000
ENTRYPOINT ["gradle", "bootRun", "-i"]